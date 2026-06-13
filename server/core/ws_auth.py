"""WebSocket authentication middleware."""

from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from django.conf import settings

from core.models import DeviceIdentifier, Workspace


@database_sync_to_async
def _get_device(device_hash: str):
    try:
        return DeviceIdentifier.objects.get(hash=device_hash, is_active=True)
    except DeviceIdentifier.DoesNotExist:
        return None


@database_sync_to_async
def _get_workspace(workspace_id, device):
    if workspace_id is None:
        return None
    try:
        return Workspace.objects.get(id=workspace_id, device=device, is_active=True)
    except Workspace.DoesNotExist:
        return None


@database_sync_to_async
def _touch_device(device):
    device.save(update_fields=["last_seen_at"])


class DeviceAuthWsMiddleware:
    """Parse auth from query string; attach device/workspace to scope."""

    def __init__(self, inner):
        self.inner = inner

    async def __call__(self, scope, receive, send):
        if scope["type"] != "websocket":
            return await self.inner(scope, receive, send)

        query = parse_qs(scope.get("query_string", b"").decode())
        api_key = query.get("api_key", [""])[0]
        device_hash = query.get("device_hash", [""])[0]
        workspace_id_raw = query.get("workspace_id", [None])[0]

        scope["ws_authenticated"] = False
        scope["device"] = None
        scope["workspace"] = None
        scope["pending_auth"] = True

        if api_key and device_hash:
            if api_key != settings.API_KEY:
                scope["auth_error"] = "invalid_api_key"
            else:
                device = await _get_device(device_hash)
                if device is None:
                    scope["auth_error"] = "device_not_registered"
                else:
                    await _touch_device(device)
                    scope["device"] = device
                    scope["ws_authenticated"] = True
                    scope["pending_auth"] = False
                    if workspace_id_raw:
                        try:
                            ws_id = int(workspace_id_raw)
                        except (TypeError, ValueError):
                            ws_id = None
                        if ws_id:
                            scope["workspace"] = await _get_workspace(ws_id, device)

        return await self.inner(scope, receive, send)
