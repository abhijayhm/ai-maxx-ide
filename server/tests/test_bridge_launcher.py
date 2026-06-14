"""Verify cursor-sdk bridge launches on Windows (direct node.exe argv)."""

import sys
import tempfile

import pytest

from agents.bridge_launcher import _bridge_command_prefix, launch_bridge_safe


@pytest.mark.skipif(sys.platform != "win32", reason="Windows bridge launcher")
def test_bridge_command_prefix_uses_node_not_cmd():
    prefix = _bridge_command_prefix()
    assert len(prefix) >= 1
    first = prefix[0].lower()
    assert first.endswith("node.exe") or not first.endswith(".cmd")


@pytest.mark.skipif(sys.platform != "win32", reason="Windows bridge launcher")
def test_auth_tokens_never_start_with_dash(monkeypatch):
    """Bridge JS treats argv values starting with '-' as missing flags."""
    import cursor_sdk._tool_callback as tc

    monkeypatch.setattr(tc.secrets, "token_urlsafe", lambda _n: "-dash-only-token")
    for _ in range(20):
        assert not tc._new_auth_token().startswith("-")


@pytest.mark.skipif(sys.platform != "win32", reason="Windows bridge launcher")
def test_launch_bridge_safe():
    bridge = launch_bridge_safe(tempfile.mkdtemp())
    try:
        assert bridge.endpoint.url.startswith("http://")
    finally:
        bridge.close()
