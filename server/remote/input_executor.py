"""Remote input staging and execution stubs."""

from django.conf import settings

_staging_buffer: list[dict] = []
_executed: list[dict] = []


def get_staging() -> list[dict]:
    return list(_staging_buffer)


def clear_staging() -> None:
    _staging_buffer.clear()


def stage_events(events: list[dict]) -> None:
    _staging_buffer.extend(events)


def get_executed() -> list[dict]:
    return list(_executed)


def clear_executed() -> None:
    _executed.clear()


def _normalize_event(event: dict) -> dict:
    """Map mobile client frames (`action`) to executor ops (`op`)."""
    normalized = dict(event)
    if "op" not in normalized and "action" in normalized:
        action = normalized.pop("action")
        if action == "click":
            normalized["op"] = "click"
        elif action == "key":
            key = normalized.pop("key", "")
            normalized["op"] = "key_combo"
            normalized["keys"] = [key] if key else []
        elif action in ("pointer_move", "move"):
            normalized["op"] = "pointer_move"
        else:
            normalized["op"] = action
    return normalized


def execute_batch(events: list[dict], dispatch: bool = False) -> list[dict]:
    """Execute input events. Uses pynput when available, otherwise records stubs."""
    if not settings.REMOTE_INPUT_ENABLED:
        return []

    events = [_normalize_event(event) for event in events]

    to_run: list[dict] = []
    if dispatch:
        to_run = list(_staging_buffer) + list(events)
        _staging_buffer.clear()
    else:
        _staging_buffer.extend(events)
        return []

    executed = []
    for event in to_run:
        result = _execute_event(event)
        executed.append(result)
        _executed.append(result)
    return executed


def _pointer_result(op: str, abs_x: int, abs_y: int, **extra) -> dict:
    from remote.cursor import normalize_position, set_cursor_position

    set_cursor_position(abs_x, abs_y)
    nx, ny = normalize_position(abs_x, abs_y)
    return {
        "op": op,
        "x": abs_x,
        "y": abs_y,
        "normalized_x": nx,
        "normalized_y": ny,
        "executed": True,
        **extra,
    }


def _execute_event(event: dict) -> dict:
    op = event.get("op", "")

    try:
        if op == "pointer_move":
            return _execute_pointer(event)
        if op == "pointer_delta":
            return _execute_pointer_delta(event)
        if op == "click":
            return _execute_click(event)
        if op == "key_combo":
            return execute_combo(event.get("keys", []))
    except ImportError:
        pass

    return {"op": op, "stub": True, **event}


def execute_combo(keys: list[str]) -> dict:
    try:
        from pynput.keyboard import Controller as KbdController, Key

        ctrl = KbdController()
        key_map = {
            "ctrl": Key.ctrl,
            "shift": Key.shift,
            "alt": Key.alt,
            "meta": Key.cmd,
            "win": Key.cmd,
            "esc": Key.esc,
            "enter": Key.enter,
            "tab": Key.tab,
        }
        parsed = []
        for k in keys:
            kl = k.lower()
            parsed.append(key_map.get(kl, k))

        for key in parsed[:-1]:
            ctrl.press(key)
        ctrl.press(parsed[-1])
        ctrl.release(parsed[-1])
        for key in reversed(parsed[:-1]):
            ctrl.release(key)
        return {"op": "key_combo", "keys": keys, "executed": True}
    except ImportError:
        return {"op": "key_combo", "keys": keys, "stub": True}


def execute_pointer(event: dict) -> dict:
    return _execute_pointer(event)


def _execute_pointer(event: dict) -> dict:
    try:
        from pynput.mouse import Controller as MouseController

        from remote.cursor import primary_monitor

        mouse = MouseController()
        x, y = event.get("x", 0), event.get("y", 0)
        monitor = primary_monitor()
        if event.get("normalized"):
            abs_x = int(monitor["left"] + x * monitor["width"])
            abs_y = int(monitor["top"] + y * monitor["height"])
        else:
            abs_x, abs_y = int(x), int(y)
        mouse.position = (abs_x, abs_y)
        return _pointer_result("pointer_move", abs_x, abs_y)
    except ImportError:
        return {"op": "pointer_move", "stub": True, **event}


def _execute_pointer_delta(event: dict) -> dict:
    try:
        from pynput.mouse import Controller as MouseController

        from remote.cursor import primary_monitor

        mouse = MouseController()
        monitor = primary_monitor()
        dx = float(event.get("dx", 0)) * monitor["width"]
        dy = float(event.get("dy", 0)) * monitor["height"]
        cur_x, cur_y = mouse.position
        abs_x = int(cur_x + dx)
        abs_y = int(cur_y + dy)
        mouse.position = (abs_x, abs_y)
        return _pointer_result("pointer_delta", abs_x, abs_y)
    except ImportError:
        return {"op": "pointer_delta", "stub": True, **event}


def _execute_click(event: dict) -> dict:
    try:
        from pynput.mouse import Button, Controller as MouseController

        mouse = MouseController()
        button_name = event.get("button", "left")
        button = Button.left if button_name == "left" else Button.right
        mouse.click(button)
        return {"op": "click", "button": button_name, "executed": True}
    except ImportError:
        return {"op": "click", "stub": True, **event}
