import json
import uuid

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer

from agents.cursor_bridge import send_message, stop_run
from core.models import AgentMessage, AgentSession, Sender, Workspace
from core.models import DeviceIdentifier


def _debug(message: str) -> None:
    print(f"[agent.ws] {message}", flush=True)


@database_sync_to_async
def get_workspace(workspace_id, device_id):
    try:
        return Workspace.objects.get(id=workspace_id, device_id=device_id, is_active=True)
    except Workspace.DoesNotExist:
        return None


@database_sync_to_async
def get_agent_session(session_id, workspace_id, device_id):
    try:
        return AgentSession.objects.get(
            id=session_id, workspace_id=workspace_id, device_id=device_id
        )
    except AgentSession.DoesNotExist:
        return None


@database_sync_to_async
def save_message(device_id, workspace_id, session_id, run_id, payload, sender, receiver):
    AgentMessage.objects.create(
        device_id=device_id,
        workspace_id=workspace_id,
        agent_session_id=session_id,
        run_id=run_id,
        sender=sender,
        receiver=receiver,
        payload=payload,
    )


class AgentConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.authenticated = self.scope.get("ws_authenticated", False)
        self.device = self.scope.get("device")
        self.workspace = self.scope.get("workspace")
        if self.authenticated:
            await self.accept()
            _debug(
                f"connected device_id={getattr(self.device, 'id', None)} "
                f"workspace_id={getattr(self.workspace, 'id', None)}"
            )
        else:
            self.pending_auth = True
            await self.accept()
            _debug("connected pending auth frame")

    async def disconnect(self, close_code):
        _debug(f"disconnected close_code={close_code}")
        self.authenticated = False
        self.device = None
        self.workspace = None

    async def receive(self, text_data=None, bytes_data=None):
        if text_data is None:
            return
        _debug(f"receive raw={text_data!r}")
        try:
            content = json.loads(text_data)
        except json.JSONDecodeError:
            _debug("invalid JSON")
            await self.send_json({"type": "error", "code": "invalid_json", "message": "Invalid JSON"})
            return

        msg_type = content.get("type")
        _debug(f"frame type={msg_type!r}")

        if msg_type == "auth":
            await self._handle_auth(content)
            return

        if not self.authenticated:
            _debug("reject unauthenticated frame")
            await self.close(code=4401)
            return

        if msg_type == "message":
            await self._handle_message(content)
        elif msg_type == "stop":
            await self._handle_stop(content)
        else:
            _debug(f"unknown type={msg_type!r}")

    async def _handle_auth(self, content):
        from django.conf import settings

        api_key = content.get("api_key", "")
        device_hash = content.get("device_hash", "")
        workspace_id = content.get("workspace_id")
        _debug(f"auth workspace_id={workspace_id!r} device_hash={device_hash[:8] if device_hash else ''}…")

        if api_key != settings.API_KEY:
            await self.send_json({"type": "error", "code": "invalid_api_key", "message": "Invalid API key"})
            await self.close(code=4401)
            return

        device = await database_sync_to_async(
            lambda: DeviceIdentifier.objects.filter(hash=device_hash, is_active=True).first()
        )()
        if not device:
            await self.send_json({"type": "error", "code": "device_not_registered", "message": "Device not registered"})
            await self.close(code=4401)
            return

        self.device = device
        self.authenticated = True

        if workspace_id:
            self.workspace = await get_workspace(workspace_id, device.id)

        await self.send_json({"type": "auth_ok"})
        _debug(f"auth_ok device_id={device.id} workspace_id={getattr(self.workspace, 'id', None)}")

    async def _handle_message(self, content):
        if not self.workspace:
            workspace_id = content.get("workspace_id")
            if workspace_id and self.device:
                self.workspace = await get_workspace(workspace_id, self.device.id)

        if not self.workspace:
            _debug("message rejected — workspace required")
            await self.send_json({"type": "error", "code": "workspace_required", "message": "Workspace required"})
            return

        session_id = content.get("session_id")
        if session_id is None:
            _debug("message rejected — session_id required")
            await self.send_json(
                {"type": "error", "code": "session_required", "message": "session_id required"}
            )
            return

        agent_session = await get_agent_session(
            int(session_id), self.workspace.id, self.device.id
        )
        if agent_session is None:
            _debug(f"message rejected — unknown session_id={session_id}")
            await self.send_json(
                {"type": "error", "code": "session_not_found", "message": "Session not found"}
            )
            return

        text = content.get("text", "")
        model = content.get("model")
        agent_mode = content.get("agent_mode") or content.get("mode")
        run_id = str(uuid.uuid4())
        preview = text if len(text) <= 120 else f"{text[:120]}…"
        _debug(
            f"message workspace_id={self.workspace.id} session_id={session_id} "
            f"run_id={run_id} model={model!r} agent_mode={agent_mode!r} text={preview!r}"
        )

        await save_message(
            self.device.id,
            self.workspace.id,
            agent_session.id,
            run_id,
            {"text": text, "model": model, "agent_mode": agent_mode},
            Sender.USER,
            Sender.SYSTEM,
        )

        try:
            async for event in send_message(
                self.workspace,
                agent_session,
                text,
                model=model,
                agent_mode=agent_mode,
            ):
                event_type = event.get("type")
                if event_type == "run_started":
                    run_id = event.get("run_id", run_id)
                    _debug(f"run_started run_id={run_id}")
                elif event_type == "stream":
                    chunk = event.get("text") or ""
                    if chunk:
                        _debug(f"stream chunk_len={len(chunk)}")
                elif event_type == "run_finished":
                    _debug(f"run_finished status={event.get('status')!r}")
                elif event_type == "error":
                    _debug(f"stream error={event.get('message')!r}")

                await self.send(text_data=json.dumps(event))
                if event.get("type") == "stream":
                    await save_message(
                        self.device.id,
                        self.workspace.id,
                        agent_session.id,
                        run_id,
                        event.get("message", {}),
                        Sender.SYSTEM,
                        Sender.USER,
                    )
        except Exception as exc:
            _debug(f"agent_error error={exc!r}")
            await self.send_json({"type": "error", "code": "agent_error", "message": str(exc)})

    async def _handle_stop(self, content):
        session_id = content.get("session_id")
        _debug(f"stop workspace_id={getattr(self.workspace, 'id', None)} session_id={session_id}")
        if session_id is not None:
            await stop_run(int(session_id))
        await self.send_json({"type": "stopped"})

    async def send_json(self, content):
        await self.send(text_data=json.dumps(content))
