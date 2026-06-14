"""Read and normalize system cursor position for remote desktop."""

from __future__ import annotations

import sys
import threading

_lock = threading.Lock()
_known_position: tuple[int, int] | None = None


def set_cursor_position(abs_x: int, abs_y: int) -> None:
    global _known_position
    with _lock:
        _known_position = (int(abs_x), int(abs_y))


def read_cursor_position() -> tuple[int, int]:
    with _lock:
        known = _known_position

    if sys.platform == "win32":
        try:
            import ctypes

            class _Point(ctypes.Structure):
                _fields_ = [("x", ctypes.c_long), ("y", ctypes.c_long)]

            pt = _Point()
            if ctypes.windll.user32.GetCursorPos(ctypes.byref(pt)):
                return int(pt.x), int(pt.y)
        except Exception:
            pass

    try:
        from pynput.mouse import Controller as MouseController

        pos = MouseController().position
        return int(pos[0]), int(pos[1])
    except Exception:
        pass

    if known is not None:
        return known
    return 0, 0


def primary_monitor() -> dict:
    import mss

    with mss.mss() as sct:
        return dict(sct.monitors[1])


def normalize_position(abs_x: int, abs_y: int, monitor: dict | None = None) -> tuple[float, float]:
    mon = monitor or primary_monitor()
    width = max(mon.get("width", 1), 1)
    height = max(mon.get("height", 1), 1)
    left = mon.get("left", 0)
    top = mon.get("top", 0)
    nx = (abs_x - left) / width
    ny = (abs_y - top) / height
    return max(0.0, min(1.0, nx)), max(0.0, min(1.0, ny))
