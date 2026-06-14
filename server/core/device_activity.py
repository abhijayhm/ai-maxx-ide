"""Throttled device activity updates — avoids SQLite write storms under ASGI."""

import time

from django.db import OperationalError
from django.utils import timezone

from core.models import DeviceIdentifier

_TOUCH_INTERVAL_SEC = 30.0
_last_touch: dict[int, float] = {}


def touch_device(device: DeviceIdentifier) -> None:
    """Bump ``last_seen_at`` at most once per interval per device."""
    if device.pk is None:
        return

    now = time.monotonic()
    last = _last_touch.get(device.pk, 0.0)
    if now - last < _TOUCH_INTERVAL_SEC:
        return

    try:
        DeviceIdentifier.objects.filter(pk=device.pk).update(
            last_seen_at=timezone.now()
        )
        _last_touch[device.pk] = now
    except OperationalError:
        # Do not fail the request when SQLite is briefly contended.
        pass
