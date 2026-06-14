"""Cursor SDK bridge — local agent per workspace with resumed conversation."""

from __future__ import annotations

import os
import traceback
import uuid
from dataclasses import asdict, is_dataclass

from channels.db import database_sync_to_async
from django.conf import settings

from agents.bridge_launcher import close_bridge, get_bridge_async

# Temporary: set False in production to yield WS error frames instead of crashing.
RAISE_ERROR = True

_bridge_override = None
_running: dict[int, dict] = {}


def _debug(message: str) -> None:
    print(f"[agent.bridge] {message}", flush=True)


def _debug_exception(exc: BaseException, workspace) -> None:
    _debug(
        f"cursor SDK failed workspace_id={workspace.id} "
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
def _persist_agent_id(workspace, agent_id: str) -> None:
    if workspace.cursor_agent_id == agent_id:
        return
    workspace.cursor_agent_id = agent_id
    workspace.save(update_fields=["cursor_agent_id", "updated_at"])


@database_sync_to_async
def _clear_agent_id(workspace) -> None:
    if not workspace.cursor_agent_id:
        return
    workspace.cursor_agent_id = ""
    workspace.save(update_fields=["cursor_agent_id", "updated_at"])


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
    """Return persisted Cursor agent id for workspace (created on first send)."""
    if _bridge_override:
        return _bridge_override(workspace)

    if not settings.CURSOR_API_KEY:
        agent_id = workspace.cursor_agent_id or f"agent-stub-{workspace.id}"
        _debug(f"bind stub workspace_id={workspace.id} agent_id={agent_id}")
        return agent_id

    if workspace.cursor_agent_id:
        _debug(f"bind existing workspace_id={workspace.id} agent_id={workspace.cursor_agent_id}")
        return workspace.cursor_agent_id

    _debug(f"bind deferred workspace_id={workspace.id} (agent created on first message)")
    return None


def _payload(message) -> dict:
    if is_dataclass(message):
        return asdict(message)
    if isinstance(message, dict):
        return message
    return {"text": str(message)}


def _extract_stream_text(payload: dict) -> str | None:
    """Normalize Cursor SDK stream messages to displayable text."""
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


def _send_options(mode: str | None):
    from cursor_sdk.types import ModelSelection, SendOptions

    model_id = mode or "composer-2.5"
    return SendOptions(model=ModelSelection(id=model_id))


async def _create_agent(client, workspace, mode: str | None):
    from cursor_sdk.types import LocalAgentOptions

    model = mode or "composer-2.5"
    _debug(f"send create workspace_id={workspace.id} model={model!r}")
    agent = await client.agents.create(
        model=model,
        api_key=settings.CURSOR_API_KEY,
        local=LocalAgentOptions(
            cwd=workspace.absolute_path,
            setting_sources=["project", "user"],
        ),
    )
    _debug(f"create ok workspace_id={workspace.id} agent_id={agent.agent_id}")
    await _persist_agent_id(workspace, agent.agent_id)
    return agent


async def _resume_agent(client, workspace):
    from cursor_sdk.types import AgentOptions

    _debug(
        f"send resume workspace_id={workspace.id} "
        f"agent_id={workspace.cursor_agent_id}"
    )
    return await client.agents.resume(
        workspace.cursor_agent_id,
        AgentOptions(api_key=settings.CURSOR_API_KEY),
    )


async def _resolve_agent(client, workspace, mode: str | None):
    """Return (agent, resumed). Prefer _start_agent_run() at call sites."""
    if workspace.cursor_agent_id:
        try:
            agent = await _resume_agent(client, workspace)
            _debug(f"resume ok workspace_id={workspace.id} agent_id={agent.agent_id}")
            return agent, True
        except Exception as exc:
            _debug(
                f"resume failed workspace_id={workspace.id} "
                f"agent_id={workspace.cursor_agent_id!r} error={exc!r}; creating fresh"
            )
            await _clear_agent_id(workspace)
            workspace.cursor_agent_id = ""

    agent = await _create_agent(client, workspace, mode)
    return agent, False


async def _agent_send(agent, text: str, mode: str | None):
    if isinstance(agent, tuple):
        agent = agent[0]
    return await agent.send(text, _send_options(mode))


async def _start_agent_run(client, workspace, text: str, mode: str | None):
    """Resolve or create agent, send prompt, recover from stale resume."""
    resumed = False
    agent = None

    if workspace.cursor_agent_id:
        try:
            agent = await _resume_agent(client, workspace)
            resumed = True
            _debug(f"resume ok workspace_id={workspace.id} agent_id={agent.agent_id}")
        except Exception as exc:
            _debug(
                f"resume failed workspace_id={workspace.id} "
                f"agent_id={workspace.cursor_agent_id!r} error={exc!r}; creating fresh"
            )
            await _clear_agent_id(workspace)
            workspace.cursor_agent_id = ""

    if agent is None:
        agent = await _create_agent(client, workspace, mode)
        resumed = False

    try:
        return await _agent_send(agent, text, mode)
    except Exception as exc:
        if not resumed or not workspace.cursor_agent_id:
            raise
        _debug(
            f"send failed after resume workspace_id={workspace.id} "
            f"agent_id={workspace.cursor_agent_id!r} error={exc!r}; recreating agent"
        )
        await _clear_agent_id(workspace)
        workspace.cursor_agent_id = ""
        fresh = await _create_agent(client, workspace, mode)
        return await _agent_send(fresh, text, mode)


async def _open_client(workspace):
    from cursor_sdk import AsyncClient

    bridge_url, bridge_token = _bridge_from_env()
    if bridge_url and bridge_token:
        _debug(f"connect external bridge url={bridge_url}")
        return AsyncClient.connect(base_url=bridge_url, auth_token=bridge_token), None

    bridge = await get_bridge_async(workspace.absolute_path)
    _debug(f"using managed bridge workspace={workspace.absolute_path!r}")
    return (
        AsyncClient(bridge.endpoint, allow_api_key_env_fallback=True),
        bridge,
    )


async def send_message(workspace, text: str, mode: str | None = None):
    """Send message to Cursor agent; yields stream events."""
    _debug(
        f"send_message workspace_id={workspace.id} "
        f"text_len={len(text)} mode={mode!r} agent_id={workspace.cursor_agent_id!r}"
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
        _running[workspace.id] = {"run_id": run_id, "running": True}
        yield {"type": "run_started", "run_id": run_id}
        yield {
            "type": "stream",
            "message": {"type": "assistant", "text": f"Stub: {text}"},
            "text": f"Stub: {text}",
        }
        _running.pop(workspace.id, None)
        yield {"type": "run_finished", "status": "completed"}
        return

    client = None
    try:
        client, _bridge = await _open_client(workspace)
        _debug(f"client open workspace_id={workspace.id}")

        model_id = mode or "composer-2.5"
        _debug(f"agent send workspace_id={workspace.id} model={model_id!r}")
        run = await _start_agent_run(client, workspace, text, mode)
        run_id = getattr(run, "run_id", getattr(run, "id", str(uuid.uuid4())))
        _debug(f"run started workspace_id={workspace.id} run_id={run_id}")
        _running[workspace.id] = {"run_id": run_id, "run": run, "running": True}
        yield {"type": "run_started", "run_id": run_id}

        async for message in run.messages():
            payload = _payload(message)
            text_chunk = _extract_stream_text(payload)
            msg_type = payload.get("type", type(message).__name__)
            preview = (text_chunk or "")[:120]
            _debug(
                f"stream workspace_id={workspace.id} run_id={run_id} "
                f"type={msg_type!r} text_len={len(text_chunk or '')} "
                f"preview={preview!r}"
            )
            frame = {"type": "stream", "message": payload}
            if text_chunk:
                frame["text"] = text_chunk
            yield frame

        _debug(f"run wait workspace_id={workspace.id} run_id={run_id}")
        result = await run.wait()
        _running.pop(workspace.id, None)
        status = getattr(result, "status", None) or (
            result.get("status") if isinstance(result, dict) else "completed"
        )
        _debug(f"run_finished workspace_id={workspace.id} run_id={run_id} status={status!r}")
        yield {
            "type": "run_finished",
            "status": status,
            "result": serialize_message(result),
        }
    except Exception as exc:
        _debug_exception(exc, workspace)
        _running.pop(workspace.id, None)
        if RAISE_ERROR:
            raise
        run_id = str(uuid.uuid4())
        _running[workspace.id] = {"run_id": run_id, "running": True}
        yield {"type": "run_started", "run_id": run_id}
        yield {
            "type": "error",
            "code": "agent_error",
            "message": str(exc),
        }
        _running.pop(workspace.id, None)
        yield {"type": "run_finished", "status": "error"}
    finally:
        if client is not None:
            await client.aclose()


async def stop_run(workspace_id: int) -> bool:
    state = _running.get(workspace_id)
    if not state:
        _debug(f"stop_run workspace_id={workspace_id} — no active run")
        return False
    run = state.get("run")
    if run and hasattr(run, "cancel"):
        await run.cancel()
    _running.pop(workspace_id, None)
    _debug(f"stop_run workspace_id={workspace_id} cancelled")
    return True


def get_status(workspace_id: int) -> dict:
    state = _running.get(workspace_id)
    if state:
        return {"running": True, "run_id": state.get("run_id", "")}
    return {"running": False, "run_id": ""}


def serialize_message(obj):
    if is_dataclass(obj):
        return asdict(obj)
    if isinstance(obj, dict):
        return obj
    return {"text": str(obj)}
