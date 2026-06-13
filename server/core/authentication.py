"""Device API key authentication for DRF."""

from django.conf import settings
from rest_framework import authentication, exceptions

from core.models import DeviceIdentifier


class DeviceAPIKeyAuthentication(authentication.BaseAuthentication):
    """Authenticate via X-API-Key and X-Device-Identifier headers."""

    def authenticate(self, request):
        path = request.path
        if path.endswith("/health/") or path.endswith("/devices/register/"):
            return None

        api_key = request.headers.get("X-API-Key", "")
        if api_key != settings.API_KEY:
            raise exceptions.AuthenticationFailed(
                detail="Invalid API key.", code="invalid_api_key"
            )

        device_hash = request.headers.get("X-Device-Identifier", "")
        if not device_hash:
            raise exceptions.AuthenticationFailed(
                detail="Device identifier required.", code="device_not_registered"
            )

        try:
            device = DeviceIdentifier.objects.get(hash=device_hash, is_active=True)
        except DeviceIdentifier.DoesNotExist as exc:
            raise exceptions.AuthenticationFailed(
                detail="Device not registered.", code="device_not_registered"
            ) from exc

        device.save(update_fields=["last_seen_at"])
        request.device = device
        return (device, None)
