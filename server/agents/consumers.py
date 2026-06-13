import json
import uuid

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from django.utils import timezone

from agents.cursor_bridge import send_message, stop_run
from core.models import AgentMessage, Sender, Workspace
from core.models import DeviceIdentifier


@database_sync_to_async
def get_workspace(workspace_id, device_id):
    try:
        return Workspace.objects.get(id=workspace_id, device_id=device_id, is_active=True)
    except Workspace.DoesNotExist:
        return None


@database_sync_to_async
def save_message(device_id, workspace_id, run_id, payload, sender, receiver):
    AgentMessage.objects.create(
        device_id=device_id,
        workspace_id=workspace_id,
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
        else:
            self.pending_auth = True
            await self.accept()

    async def disconnect(self, close_code):
        self.authenticated = False
        self.device = None
        self.workspace = None

    async def receive(self, text_data=None, bytes_data=None):
        if text_data is None:
            return
        try:
            content = json.loads(text_data)
        except json.JSONDecodeError:
            await self.send_json({"type": "error", "code": "invalid_json", "message": "Invalid JSON"})
            return

        msg_type = content.get("type")

        if msg_type == "auth":
            await self._handle_auth(content)
            return

        if not self.authenticated:
            await self.close(code=4401)
            return

        if msg_type == "message":
            await self._handle_message(content)
        elif msg_type == "stop":
            await self._handle_stop()

    async def _handle_auth(self, content):
        from django.conf import settings

        api_key = content.get("api_key", "")
        device_hash = content.get("device_hash", "")
        workspace_id = content.get("workspace_id")

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

    async def _handle_message(self, content):
        if not self.workspace:
            workspace_id = content.get("workspace_id")
            if workspace_id and self.device:
                self.workspace = await get_workspace(workspace_id, self.device.id)

        if not self.workspace:
            await self.send_json({"type": "error", "code": "workspace_required", "message": "Workspace required"})
            return

        text = content.get("text", "")
        mode = content.get("mode")
        run_id = str(uuid.uuid4())

        await save_message(
            self.device.id,
            self.workspace.id,
            run_id,
            {"text": text, "mode": mode},
            Sender.USER,
            Sender.SYSTEM,
        )

        try:
            async for event in send_message(self.workspace, text, mode=mode):
                if event.get("type") == "run_started":
                    run_id = event.get("run_id", run_id)
                await self.send(text_data=json.dumps(event))
                if event.get("type") == "stream":
                    await save_message(
                        self.device.id,
                        self.workspace.id,
                        run_id,
                        event.get("message", {}),
                        Sender.SYSTEM,
                        Sender.USER,
                    )
        except Exception as exc:
            await self.send_json({"type": "error", "code": "agent_error", "message": str(exc)})

    async def _handle_stop(self):
        if self.workspace:
            await stop_run(self.workspace.id)
        await self.send_json({"type": "stopped"})

    async def send_json(self, content):
        await self.send(text_data=json.dumps(content))
