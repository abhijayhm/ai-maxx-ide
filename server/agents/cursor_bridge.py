"""Cursor SDK bridge — session-scoped agents with in-memory reuse."""

from __future__ import annotations

import os
import traceback
import uuid
from dataclasses import asdict, is_dataclass
from typing import Any

from channels.db import database_sync_to_async
from django.conf import settings

from agents.bridge_launcher import get_bridge_async

# Temporary: set False in production to yield WS error frames instead of crashing.
RAISE_ERROR = True

_bridge_override = None
_running: dict[int, dict] = {}
_session_agents: dict[int, Any] = {}
_workspace_clients: dict[str, Any] = {}


def _debug(message: str) -> None:
    print(f"[agent.bridge] {message}", flush=True)


def _debug_exception(exc: BaseException, workspace, session_id: int | None = None) -> None:
    _debug(
        f"cursor SDK failed workspace_id={workspace.id} session_id={session_id} "
        f"type={type(exc).__name__} error={exc!r}"
    )
    for attr in ("code", "status", "request_id", "message"):
        value = getattr(exc, attr, None)
        if value is not None:
            _debug(f"  {attr}={value!r}")
    _debug(f"traceback:\n{traceback.format_exc()}")


def set_bridge_override(fn):
    global _bridge_override
    _bridge_override = fn


@database_sync_to_async
def _persist_session_agent_id(session, agent_id: str) -> None:
    if session.cursor_agent_id == agent_id:
        return
    session.cursor_agent_id = agent_id
    session.save(update_fields=["cursor_agent_id", "updated_at"])


@database_sync_to_async
def _clear_session_agent_id(session) -> None:
    if not session.cursor_agent_id:
        return
    session.cursor_agent_id = ""
    session.save(update_fields=["cursor_agent_id", "updated_at"])


def _bridge_from_env():
    url = os.environ.get("CURSOR_SDK_BRIDGE_URL") or getattr(
        settings, "CURSOR_SDK_BRIDGE_URL", ""
    )
    token = (
        os.environ.get("CURSOR_SDK_BRIDGE_TOKEN")
        or os.environ.get("CURSOR_SDK_BRIDGE_AUTH_TOKEN")
        or getattr(settings, "CURSOR_SDK_BRIDGE_TOKEN", "")
    )
    if url and token:
        return url.strip(), token.strip()
    return None, None


def bind_cursor_agent(workspace) -> str | None:
    """Legacy bind helper — sessions own agents now."""
    if _bridge_override:
        return _bridge_override(workspace)

    if not settings.CURSOR_API_KEY:
        return workspace.cursor_agent_id or f"agent-stub-{workspace.id}"

    return workspace.cursor_agent_id or None


def _payload(message) -> dict:
    if is_dataclass(message):
        return asdict(message)
    if isinstance(message, dict):
        return message
    return {"text": str(message)}


def _extract_stream_text(payload: dict) -> str | None:
    msg_type = payload.get("type")
    if msg_type == "assistant":
        message = payload.get("message", {})
        content = message.get("content", []) if isinstance(message, dict) else []
        if not isinstance(content, list):
            return None
        parts: list[str] = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(block.get("text", ""))
        joined = "".join(parts)
        return joined or None
    if msg_type == "thinking":
        text = payload.get("text")
        return text if text else None
    if msg_type in ("tool_call", "status"):
        name = payload.get("name") or payload.get("status") or msg_type
        status = payload.get("status", "")
        return f"[{msg_type}] {name} {status}".strip()
    text = payload.get("text")
    return text if text else None


def _normalize_agent_mode(agent_mode: str | None) -> str | None:
    if agent_mode in ("agent", "plan"):
        return agent_mode
    return None


def _resolve_model_id(model_id: str | None) -> str | None:
    if not model_id or model_id == "auto":
        return None
    return model_id


def _send_options(model_id: str | None, agent_mode: str | None = None):
    from cursor_sdk.types import ModelSelection, SendOptions

    kwargs: dict = {}
    resolved = _resolve_model_id(model_id)
    if resolved:
        kwargs["model"] = ModelSelection(id=resolved)
    normalized = _normalize_agent_mode(agent_mode)
    if normalized is not None:
        kwargs["mode"] = normalized
    return SendOptions(**kwargs)


async def _get_client(workspace):
    from cursor_sdk import AsyncClient

    path = workspace.absolute_path
    cached = _workspace_clients.get(path)
    if cached is not None:
        return cached

    bridge_url, bridge_token = _bridge_from_env()
    if bridge_url and bridge_token:
        _debug(f"connect external bridge url={bridge_url}")
        client = AsyncClient.connect(base_url=bridge_url, auth_token=bridge_token)
    else:
        bridge = await get_bridge_async(path)
        _debug(f"using managed bridge workspace={path!r}")
        client = AsyncClient(bridge.endpoint, allow_api_key_env_fallback=True)

    _workspace_clients[path] = client
    return client


async def _create_agent(client, workspace, session, model_id: str | None):
    from cursor_sdk.types import LocalAgentOptions

    model = _resolve_model_id(model_id) or "composer-2.5"
    _debug(
        f"send create workspace_id={workspace.id} session_id={session.id} "
        f"model={model!r}"
    )
    agent = await client.agents.create(
        model=model,
        api_key=settings.CURSOR_API_KEY,
        local=LocalAgentOptions(
            cwd=workspace.absolute_path,
            setting_sources=["project", "user"],
        ),
    )
    _debug(
        f"create ok workspace_id={workspace.id} session_id={session.id} "
        f"agent_id={agent.agent_id}"
    )
    await _persist_session_agent_id(session, agent.agent_id)
    session.cursor_agent_id = agent.agent_id
    _session_agents[session.id] = agent
    return agent


async def _resume_agent(client, workspace, session):
    from cursor_sdk.types import AgentOptions

    _debug(
        f"send resume workspace_id={workspace.id} session_id={session.id} "
        f"agent_id={session.cursor_agent_id}"
    )
    agent = await client.agents.resume(
        session.cursor_agent_id,
        AgentOptions(api_key=settings.CURSOR_API_KEY),
    )
    _session_agents[session.id] = agent
    return agent


async def _resolve_session_agent(client, workspace, session, model_id: str | None):
    cached = _session_agents.get(session.id)
    if cached is not None:
        _debug(f"reuse cached agent session_id={session.id}")
        return cached, False

    if session.cursor_agent_id:
        try:
            agent = await _resume_agent(client, workspace, session)
            _debug(
                f"resume ok workspace_id={workspace.id} session_id={session.id} "
                f"agent_id={agent.agent_id}"
            )
            return agent, True
        except Exception as exc:
            _debug(
                f"resume failed session_id={session.id} "
                f"agent_id={session.cursor_agent_id!r} error={exc!r}; creating fresh"
            )
            await _clear_session_agent_id(session)
            session.cursor_agent_id = ""
            _session_agents.pop(session.id, None)

    agent = await _create_agent(client, workspace, session, model_id)
    return agent, False


async def _agent_send(agent, text: str, model_id: str | None, agent_mode: str | None):
    if isinstance(agent, tuple):
        agent = agent[0]
    return await agent.send(text, _send_options(model_id, agent_mode))


async def _start_agent_run(
    client, workspace, session, text: str, model_id: str | None, agent_mode: str | None
):
    agent, resumed = await _resolve_session_agent(client, workspace, session, model_id)
    try:
        return await _agent_send(agent, text, model_id, agent_mode)
    except Exception as exc:
        if not resumed or not session.cursor_agent_id:
            raise
        _debug(
            f"send failed after resume session_id={session.id} "
            f"agent_id={session.cursor_agent_id!r} error={exc!r}; recreating agent"
        )
        await _clear_session_agent_id(session)
        session.cursor_agent_id = ""
        _session_agents.pop(session.id, None)
        fresh = await _create_agent(client, workspace, session, model_id)
        return await _agent_send(fresh, text, model_id, agent_mode)


async def list_models(workspace):
    """Return available Cursor models for the workspace account."""
    if _bridge_override or not settings.CURSOR_API_KEY:
        return [{"id": "composer-2.5", "display_name": "Composer 2.5"}]

    from cursor_sdk import AsyncCursor

    client = await _get_client(workspace)
    models = await AsyncCursor.models.list(client=client)
    result = []
    for model in models:
        model_id = getattr(model, "id", None) or str(model)
        display = getattr(model, "display_name", None) or model_id
        result.append({"id": model_id, "display_name": display})
    return result


async def ensure_session_agent(workspace, session, model_id: str | None = None):
    """Create or resume the Cursor agent for a session (called on session create)."""
    if not settings.CURSOR_API_KEY or _bridge_override:
        return None
    if _session_agents.get(session.id) is not None:
        return _session_agents[session.id]
    client = await _get_client(workspace)
    agent, _ = await _resolve_session_agent(client, workspace, session, model_id)
    return agent


async def send_message(
    workspace,
    session,
    text: str,
    *,
    model: str | None = None,
    agent_mode: str | None = None,
    mode: str | None = None,
):
    """Send message to Cursor agent for a session; yields stream events."""
    model_id = model or mode
    _debug(
        f"send_message workspace_id={workspace.id} session_id={session.id} "
        f"text_len={len(text)} model={model_id!r} agent_mode={agent_mode!r} "
        f"agent_id={session.cursor_agent_id!r}"
    )

    if _bridge_override:
        result = _bridge_override(workspace, text)
        if hasattr(result, "__aiter__"):
            async for msg in result:
                yield msg
            return
        yield result
        return

    if not settings.CURSOR_API_KEY:
        run_id = str(uuid.uuid4())
        _running[session.id] = {"run_id": run_id, "running": True}
        yield {"type": "run_started", "run_id": run_id}
        yield {
            "type": "stream",
            "message": {"type": "assistant", "text": f"Stub: {text}"},
            "text": f"Stub: {text}",
        }
        _running.pop(session.id, None)
        yield {"type": "run_finished", "status": "completed"}
        return

    try:
        client = await _get_client(workspace)
        _debug(f"client open workspace_id={workspace.id} session_id={session.id}")

        resolved_model = _resolve_model_id(model_id)
        _debug(
            f"agent send workspace_id={workspace.id} "
            f"model={resolved_model!r} agent_mode={agent_mode!r}"
        )
        run = await _start_agent_run(
            client, workspace, session, text, resolved_model, agent_mode
        )
        run_id = getattr(run, "run_id", getattr(run, "id", str(uuid.uuid4())))
        _debug(f"run started session_id={session.id} run_id={run_id}")
        _running[session.id] = {"run_id": run_id, "run": run, "running": True}
        yield {"type": "run_started", "run_id": run_id}

        async for message in run.messages():
            payload = _payload(message)
            text_chunk = _extract_stream_text(payload)
            msg_type = payload.get("type", type(message).__name__)
            preview = (text_chunk or "")[:120]
            _debug(
                f"stream session_id={session.id} run_id={run_id} "
                f"type={msg_type!r} text_len={len(text_chunk or '')} "
                f"preview={preview!r}"
            )
            frame = {"type": "stream", "message": payload}
            if text_chunk:
                frame["text"] = text_chunk
            yield frame

        _debug(f"run wait session_id={session.id} run_id={run_id}")
        result = await run.wait()
        _running.pop(session.id, None)
        status = getattr(result, "status", None) or (
            result.get("status") if isinstance(result, dict) else "completed"
        )
        _debug(f"run_finished session_id={session.id} run_id={run_id} status={status!r}")
        yield {
            "type": "run_finished",
            "status": status,
            "result": serialize_message(result),
        }
    except Exception as exc:
        _debug_exception(exc, workspace, session.id)
        _running.pop(session.id, None)
        if RAISE_ERROR:
            raise
        run_id = str(uuid.uuid4())
        _running[session.id] = {"run_id": run_id, "running": True}
        yield {"type": "run_started", "run_id": run_id}
        yield {
            "type": "error",
            "code": "agent_error",
            "message": str(exc),
        }
        _running.pop(session.id, None)
        yield {"type": "run_finished", "status": "error"}


async def stop_run(session_id: int) -> bool:
    state = _running.get(session_id)
    if not state:
        _debug(f"stop_run session_id={session_id} — no active run")
        return False
    run = state.get("run")
    if run and hasattr(run, "cancel"):
        await run.cancel()
    _running.pop(session_id, None)
    _debug(f"stop_run session_id={session_id} cancelled")
    return True


def get_status(session_id: int) -> dict:
    state = _running.get(session_id)
    if state:
        return {"running": True, "run_id": state.get("run_id", "")}
    return {"running": False, "run_id": ""}


def serialize_message(obj):
    if is_dataclass(obj):
        return asdict(obj)
    if isinstance(obj, dict):
        return obj
    return {"text": str(obj)}
