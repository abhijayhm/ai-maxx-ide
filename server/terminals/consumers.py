import asyncio
import base64
import json

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from django.utils import timezone

from core.models import DeviceIdentifier
from terminals.io_service import list_terminal_io, save_terminal_io
from terminals.models import Terminal, TerminalIODirection, TerminalStatus
from terminals.pty_manager import PtyManager
from terminals.services import close_stale_terminals


@database_sync_to_async
def get_terminal(session_id, device_id, workspace_id):
    try:
        return Terminal.objects.select_related("workspace").get(
            id=session_id,
            device_id=device_id,
            workspace_id=workspace_id,
        )
    except Terminal.DoesNotExist:
        return None


@database_sync_to_async
def touch_terminal(terminal):
    terminal.last_used = timezone.now()
    terminal.save(update_fields=["last_used"])


@database_sync_to_async
def set_terminal_pid(terminal, pid):
    terminal.pid = pid
    terminal.status = TerminalStatus.ACTIVE
    terminal.last_used = timezone.now()
    terminal.save(update_fields=["pid", "status", "last_used"])


@database_sync_to_async
def close_terminal(terminal):
    terminal.pid = None
    terminal.status = TerminalStatus.CLOSED
    terminal.save(update_fields=["pid", "status"])


@database_sync_to_async
def run_close_stale(device_id, workspace_id):
    device = DeviceIdentifier.objects.get(id=device_id)
    return close_stale_terminals(device=device, workspace_id=workspace_id)


class TerminalConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.session_id = self.scope["url_route"]["kwargs"]["session_id"]
        self.device = self.scope.get("device")
        self.workspace = self.scope.get("workspace")
        self.pty = None
        self._pump_task = None
        self.authenticated = self.scope.get("ws_authenticated", False)

        if self.authenticated and self.device:
            await run_close_stale(self.device.id, self.workspace.id if self.workspace else None)
            await self.accept()
            await self._attach()
        else:
            await self.accept()

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

        if msg_type == "input" and self.pty and self.terminal:
            raw = content.get("data", "")
            data = base64.b64decode(raw)
            await save_terminal_io(
                self.terminal.id,
                TerminalIODirection.INPUT,
                raw,
            )
            await asyncio.to_thread(self.pty.write, data)
            await touch_terminal(self.terminal)
        elif msg_type == "resize" and self.pty and self.terminal:
            cols = content.get("cols", 80)
            rows = content.get("rows", 24)
            await asyncio.to_thread(self.pty.set_size, cols, rows)
            self.terminal.cols = cols
            self.terminal.rows = rows
            await touch_terminal(self.terminal)

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
            from core.models import Workspace

            self.workspace = await database_sync_to_async(
                lambda: Workspace.objects.filter(
                    id=workspace_id, device=device, is_active=True
                ).first()
            )()

        await run_close_stale(device.id, self.workspace.id if self.workspace else None)
        await self._attach()

    async def _replay_history(self):
        if not self.terminal:
            return
        history = await list_terminal_io(self.terminal.id)
        if not history:
            return
        await self.send_json(
            {
                "type": "history",
                "lines": [
                    {
                        "id": line.id,
                        "direction": line.direction,
                        "data": line.data,
                        "created_at": line.created_at.isoformat(),
                    }
                    for line in history
                ],
            }
        )

    async def _attach(self):
        if not self.workspace:
            await self.send_json({"type": "error", "code": "workspace_required", "message": "Workspace required"})
            await self.close(code=4401)
            return

        self.terminal = await get_terminal(
            self.session_id, self.device.id, self.workspace.id
        )
        if not self.terminal:
            await self.send_json({"type": "error", "code": "not_found", "message": "Terminal not found"})
            await self.close(code=4404)
            return

        if self.terminal.status == TerminalStatus.CLOSED:
            await self.send_json(
                {"type": "error", "code": "terminal_closed", "message": "idle timeout"}
            )
            await self.close(code=4403)
            return

        if self.terminal.pid:
            self.pty = PtyManager.get(self.terminal.pid)

        if not self.pty:
            self.pty = await PtyManager.spawn(
                shell=self.terminal.shell,
                cwd=self.terminal.cwd,
                cols=self.terminal.cols,
                rows=self.terminal.rows,
            )
            await set_terminal_pid(self.terminal, self.pty.pid)

        await self.send_json(
            {
                "type": "attached",
                "cols": self.terminal.cols,
                "rows": self.terminal.rows,
                "cwd": self.terminal.cwd,
                "shell": self.terminal.shell,
                "pid": self.terminal.pid,
                "status": self.terminal.status,
            }
        )
        await self._replay_history()
        self._pump_task = asyncio.create_task(self._pump_output())

    async def _pump_output(self):
        while self.pty and self.pty.isalive():
            data = await asyncio.to_thread(self.pty.read, 4096)
            if data:
                encoded = base64.b64encode(data).decode("ascii")
                if self.terminal:
                    await save_terminal_io(
                        self.terminal.id,
                        TerminalIODirection.OUTPUT,
                        encoded,
                    )
                await self.send_json({"type": "output", "data": encoded})
                if self.terminal:
                    await touch_terminal(self.terminal)
            else:
                await asyncio.sleep(0.05)

        if self.terminal:
            await close_terminal(self.terminal)
        await self.send_json({"type": "exit", "code": 0})

    async def disconnect(self, code):
        if self._pump_task:
            self._pump_task.cancel()

    async def send_json(self, content):
        await self.send(text_data=json.dumps(content))
