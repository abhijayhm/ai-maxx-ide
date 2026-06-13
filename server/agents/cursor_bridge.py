"""Mockable Cursor SDK bridge."""

import uuid
from dataclasses import asdict, is_dataclass

from django.conf import settings

_bridge_override = None
_running: dict[int, dict] = {}


def set_bridge_override(fn):
    global _bridge_override
    _bridge_override = fn


def bind_cursor_agent(workspace) -> str | None:
    """Create or resume a Cursor local agent for workspace. Returns agent_id or None."""
    if _bridge_override:
        return _bridge_override(workspace)

    if not settings.CURSOR_API_KEY:
        agent_id = workspace.cursor_agent_id or f"agent-stub-{workspace.id}"
        return agent_id

    try:
        from cursor_sdk import AsyncClient
        from cursor_sdk.types import LocalAgentOptions
    except ImportError:
        return workspace.cursor_agent_id or f"agent-stub-{workspace.id}"

    import asyncio

    async def _create():
        async with await AsyncClient.launch_bridge(workspace=workspace.absolute_path) as client:
            if workspace.cursor_agent_id:
                agent = await client.agents.resume(workspace.cursor_agent_id)
            else:
                agent = await client.agents.create(
                    model="composer-2.5",
                    api_key=settings.CURSOR_API_KEY,
                    local=LocalAgentOptions(
                        cwd=workspace.absolute_path,
                        setting_sources=["project", "user"],
                    ),
                )
            return agent.agent_id

    try:
        loop = asyncio.new_event_loop()
        try:
            return loop.run_until_complete(_create())
        finally:
            loop.close()
    except Exception:
        return None


class StubRun:
    def __init__(self, run_id: str, text: str):
        self.run_id = run_id
        self.text = text
        self._cancelled = False

    async def messages(self):
        yield {"type": "assistant", "text": f"Echo: {self.text}"}

    async def wait(self):
        return {"status": "completed", "result": self.text}

    async def cancel(self):
        self._cancelled = True


class StubAgent:
    def __init__(self, agent_id: str):
        self.agent_id = agent_id

    async def send(self, text: str, **kwargs):
        run_id = str(uuid.uuid4())
        _running[self.agent_id] = {"run_id": run_id, "run": StubRun(run_id, text)}
        return StubRun(run_id, text)


async def send_message(workspace, text: str, mode: str | None = None):
    """Send message to Cursor agent; yields stream events."""
    agent_id = workspace.cursor_agent_id or bind_cursor_agent(workspace)
    if not agent_id:
        raise RuntimeError("Cursor unavailable")

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
        yield {"type": "stream", "message": {"type": "assistant", "text": f"Stub: {text}"}}
        _running.pop(workspace.id, None)
        return

    from cursor_sdk import AsyncClient

    async with await AsyncClient.launch_bridge(workspace=workspace.absolute_path) as client:
        if workspace.cursor_agent_id:
            agent = await client.agents.resume(workspace.cursor_agent_id)
        else:
            agent = await client.agents.create(
                model=mode or "composer-2.5",
                api_key=settings.CURSOR_API_KEY,
                local={"cwd": workspace.absolute_path, "setting_sources": ["project", "user"]},
            )
        run = await agent.send(text)
        run_id = getattr(run, "run_id", str(uuid.uuid4()))
        _running[workspace.id] = {"run_id": run_id, "run": run, "running": True}
        yield {"type": "run_started", "run_id": run_id}
        async for message in run.messages():
            payload = asdict(message) if is_dataclass(message) else message
            yield {"type": "stream", "message": payload}
        result = await run.wait()
        _running.pop(workspace.id, None)
        yield {
            "type": "run_finished",
            "status": getattr(result, "status", "completed"),
            "result": result,
        }


async def stop_run(workspace_id: int) -> bool:
    state = _running.get(workspace_id)
    if not state:
        return False
    run = state.get("run")
    if run and hasattr(run, "cancel"):
        await run.cancel()
    _running.pop(workspace_id, None)
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
