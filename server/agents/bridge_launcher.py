"""Windows-safe cursor-sdk-bridge launcher.

The SDK's default discovery reader uses ``select()`` on pipe fds, which fails on
Windows (WinError 10038). We patch discovery to blocking ``readline()`` in a
worker thread via ``asyncio.to_thread``.

On Windows, ``cursor-sdk-bridge.cmd`` forwards args with ``%*``; tokens that
start with ``-`` (common for url-safe secrets) are swallowed, so we invoke the
bundled ``node.exe`` + ``cursor-sdk-bridge.js`` directly.
"""

from __future__ import annotations

import asyncio
import sys
import time
from pathlib import Path
from typing import Any

import cursor_sdk._bridge as bridge_mod
from cursor_sdk._bridge import Bridge, parse_discovery_line
from cursor_sdk.errors import CursorSDKError
from cursor_sdk.types import LocalAgentOptions

_bridges: dict[str, Bridge] = {}


def _patch_bridge_auth_tokens() -> None:
    """cursor-sdk-bridge rejects argv values that start with '-' (common for url-safe secrets)."""

    def _wrap(module_name: str) -> None:
        import importlib

        mod = importlib.import_module(module_name)
        original = mod._new_auth_token

        def _safe_auth_token() -> str:
            for _ in range(16):
                token = original()
                if token and not token.startswith("-"):
                    return token
            return f"t{original().lstrip('-')}"

        mod._new_auth_token = _safe_auth_token

    _wrap("cursor_sdk._tool_callback")
    _wrap("cursor_sdk._store_callback")


_patch_bridge_auth_tokens()


def _bridge_command_prefix() -> list[str]:
    """Argv prefix for ``Bridge.launch`` — bypass ``.cmd`` on Windows."""
    from cursor_sdk._vendor import resolve_bridge_path

    bridge_path = Path(resolve_bridge_path())
    if sys.platform == "win32" and bridge_path.suffix.lower() == ".cmd":
        bridge_bin = bridge_path.parent
        node = bridge_bin / "node.exe"
        js = bridge_bin.parent / "dist" / "bin" / "cursor-sdk-bridge.js"
        if node.is_file() and js.is_file():
            return [str(node), str(js)]
    return [str(bridge_path)]


def _read_discovery_blocking(process, timeout: float) -> dict[str, Any]:
    if process.stderr is None:
        raise CursorSDKError("Bridge process stderr is unavailable")

    deadline = time.monotonic() + timeout
    stderr_lines: list[str] = []

    while time.monotonic() < deadline:
        line = process.stderr.readline()
        if line:
            stderr_lines.append(line)
            parsed = parse_discovery_line(line)
            if parsed is not None:
                return parsed
        elif process.poll() is not None:
            break
        else:
            time.sleep(0.05)

    exit_code = process.poll()
    raise CursorSDKError(
        f"Bridge exited before discovery with status {exit_code}: "
        + "".join(stderr_lines)
    )


def launch_bridge_safe(
    workspace: str,
    *,
    local: LocalAgentOptions | None = None,
    timeout: float = 30,
) -> Bridge:
    """Launch bridge subprocess with a Windows-compatible discovery reader."""
    original = bridge_mod._read_discovery
    bridge_mod._read_discovery = _read_discovery_blocking
    try:
        return Bridge.launch(
            _bridge_command_prefix(),
            workspace=workspace,
            timeout=timeout,
            local=local,
        )
    finally:
        bridge_mod._read_discovery = original


def get_bridge(workspace_path: str) -> Bridge:
    bridge = _bridges.get(workspace_path)
    if bridge is not None and bridge.process is not None and bridge.process.poll() is None:
        return bridge
    if bridge is not None:
        try:
            bridge.close()
        except Exception:
            pass
    launched = launch_bridge_safe(
        workspace_path,
        local=LocalAgentOptions(
            cwd=workspace_path,
            setting_sources=["project", "user"],
        ),
    )
    _bridges[workspace_path] = launched
    return launched


async def get_bridge_async(workspace_path: str) -> Bridge:
    return await asyncio.to_thread(get_bridge, workspace_path)


def close_bridge(workspace_path: str) -> None:
    bridge = _bridges.pop(workspace_path, None)
    if bridge is not None:
        bridge.close()
