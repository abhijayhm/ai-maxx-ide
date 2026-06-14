"""Cursor SDK bridge — local agent per workspace with resumed conversation."""

from __future__ import annotations

import os
import uuid
from dataclasses import asdict, is_dataclass

from channels.db import database_sync_to_async
from django.conf import settings

from agents.bridge_launcher import close_bridge, get_bridge_async

_bridge_override = None
_running: dict[int, dict] = {}


def _debug(message: str) -> None:
    print(f"[agent.bridge] {message}", flush=True)


def set_bridge_override(fn):
    global _bridge_override
    _bridge_override = fn


@database_sync_to_async
def _persist_agent_id(workspace, agent_id: str) -> None:
    if workspace.cursor_agent_id == agent_id:
        return
    workspace.cursor_agent_id = agent_id
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

    return SendOptions(model=ModelSelection(id=mode or "composer-2.5"))


async def _resolve_agent(client, workspace, mode: str | None):
    from cursor_sdk.types import LocalAgentOptions

    if workspace.cursor_agent_id:
        _debug(f"send resume workspace_id={workspace.id} agent_id={workspace.cursor_agent_id}")
        return await client.agents.resume(workspace.cursor_agent_id)

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
    await _persist_agent_id(workspace, agent.agent_id)
    return agent


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
        agent = await _resolve_agent(client, workspace, mode)
        run = await agent.send(text, _send_options(mode))
        run_id = getattr(run, "run_id", getattr(run, "id", str(uuid.uuid4())))
        _running[workspace.id] = {"run_id": run_id, "run": run, "running": True}
        yield {"type": "run_started", "run_id": run_id}

        async for message in run.messages():
            payload = _payload(message)
            text_chunk = _extract_stream_text(payload)
            frame = {"type": "stream", "message": payload}
            if text_chunk:
                frame["text"] = text_chunk
            yield frame

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
        _debug(f"cursor SDK failed workspace_id={workspace.id} error={exc!r}")
        close_bridge(workspace.absolute_path)
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
