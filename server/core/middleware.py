"""HTTP middleware for device authentication."""

import json

from django.conf import settings
from django.http import JsonResponse

from core.models import DeviceIdentifier

PUBLIC_PATHS = (
    "/api/health/",
    "/api/devices/register/",
)

WS_PATH_PREFIX = "/api/ws/"


class DeviceAuthMiddleware:
    """Validate API key and device hash for protected HTTP routes."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        path = request.path
        if not path.startswith("/api/"):
            return self.get_response(request)

        # WebSockets authenticate via query string in DeviceAuthWsMiddleware.
        if path.startswith(WS_PATH_PREFIX):
            return self.get_response(request)

        if path.endswith("/devices/identifier/") or path.endswith("/devices/identifier"):
            api_key = request.headers.get("X-API-Key", "")
            if api_key != settings.API_KEY:
                return JsonResponse(
                    {"code": "invalid_api_key", "detail": "Invalid API key."},
                    status=403,
                )
            return self.get_response(request)

        if any(path.endswith(p.rstrip("/") + "/") or path == p.rstrip("/") for p in PUBLIC_PATHS):
            if path.endswith("/devices/register/") or path.endswith("/devices/register"):
                api_key = request.headers.get("X-API-Key", "")
                if api_key != settings.API_KEY:
                    return JsonResponse(
                        {"code": "invalid_api_key", "detail": "Invalid API key."},
                        status=403,
                    )
            return self.get_response(request)

        api_key = request.headers.get("X-API-Key", "")
        if api_key != settings.API_KEY:
            return JsonResponse(
                {"code": "invalid_api_key", "detail": "Invalid API key."},
                status=403,
            )

        device_hash = request.headers.get("X-Device-Identifier", "")
        if not device_hash:
            return JsonResponse(
                {"code": "device_not_registered", "detail": "Device not registered."},
                status=403,
            )

        try:
            device = DeviceIdentifier.objects.get(hash=device_hash, is_active=True)
        except DeviceIdentifier.DoesNotExist:
            return JsonResponse(
                {"code": "device_not_registered", "detail": "Device not registered."},
                status=403,
            )

        device.save(update_fields=["last_seen_at"])
        request.device = device
        request.auth_device = device
        return self.get_response(request)
