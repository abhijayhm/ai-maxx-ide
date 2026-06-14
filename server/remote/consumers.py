import json

from channels.generic.websocket import AsyncWebsocketConsumer

from core.models import DeviceIdentifier
from remote.input_executor import clear_staging, execute_batch, get_staging
from remote.webrtc import add_ice_candidate, close_peer, handle_offer


class RemoteConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.authenticated = self.scope.get("ws_authenticated", False)
        self.device = self.scope.get("device")
        self.pc = None
        self._screen_track = None
        await self.accept()
        if self.authenticated:
            await self.send_json({"type": "auth_ok", "connected": True})
            await self._send_cursor_position()

    async def disconnect(self, close_code):
        await close_peer(self.pc, self._screen_track)
        self.pc = None
        self._screen_track = None

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

        if msg_type in ("offer", "answer", "ice_candidate"):
            await self._handle_signaling(content)
        elif msg_type == "input_batch":
            await self._handle_input_batch(content)
        elif msg_type == "clear":
            clear_staging()
            await self.send_json({"type": "staging_cleared"})

    async def _handle_auth(self, content):
        from django.conf import settings

        api_key = content.get("api_key", "")
        device_hash = content.get("device_hash", "")

        if api_key != settings.API_KEY:
            await self.send_json({"type": "error", "code": "invalid_api_key", "message": "Invalid API key"})
            await self.close(code=4401)
            return

        from channels.db import database_sync_to_async

        device = await database_sync_to_async(
            lambda: DeviceIdentifier.objects.filter(hash=device_hash, is_active=True).first()
        )()
        if not device:
            await self.send_json({"type": "error", "code": "device_not_registered", "message": "Device not registered"})
            await self.close(code=4401)
            return

        self.device = device
        self.authenticated = True
        await self.send_json({"type": "auth_ok", "connected": True})
        await self._send_cursor_position()

    async def _send_cursor_position(self) -> None:
        from remote.cursor import normalize_position, read_cursor_position

        abs_x, abs_y = read_cursor_position()
        nx, ny = normalize_position(abs_x, abs_y)
        await self.send_json({"type": "pointer_position", "x": nx, "y": ny})

    async def _handle_signaling(self, content):
        msg_type = content.get("type")
        if msg_type == "offer":
            await close_peer(self.pc, self._screen_track)
            self.pc, self._screen_track = await handle_offer(
                self.send_json,
                content.get("sdp", ""),
            )
        elif msg_type == "ice_candidate":
            await add_ice_candidate(self.pc, content)

    async def _handle_input_batch(self, content):
        events = content.get("events", [])
        dispatch = content.get("dispatch", False)

        if not events and not dispatch:
            clear_staging()
            await self.send_json({"type": "staging_cleared"})
            return

        executed = execute_batch(events, dispatch=dispatch)
        await self.send_json(
            {
                "type": "input_executed" if dispatch else "input_staged",
                "count": len(executed) if dispatch else len(get_staging()),
                "executed": executed if dispatch else [],
            }
        )
        if dispatch:
            for item in executed:
                if item.get("normalized_x") is None:
                    continue
                await self.send_json(
                    {
                        "type": "pointer_position",
                        "x": item["normalized_x"],
                        "y": item["normalized_y"],
                    }
                )

    async def send_json(self, content):
        await self.send(text_data=json.dumps(content))
