import base64
import json
import sys
from datetime import timedelta

import pytest
from channels.testing.websocket import WebsocketCommunicator
from django.utils import timezone

from config.asgi import application
from terminals.models import Terminal, TerminalStatus
from terminals.output_format import format_terminal_stdout, sanitize_terminal_output
from terminals.pty_manager import PtyManager
from terminals.services import close_stale_terminals

try:
    from winpty import PtyProcess as _WinPtyProcess  # noqa: F401

    _HAS_PYWINPTY = True
except ImportError:
    _HAS_PYWINPTY = False


async def _ws_attach(communicator):
    response = await communicator.receive_json_from(timeout=10)
    assert response["type"] == "ready"
    response = await communicator.receive_json_from(timeout=10)
    assert response["type"] == "attached"
    response = await communicator.receive_json_from(timeout=10)
    assert response["type"] == "output_full"
    return response


async def _ws_execute_and_collect(communicator, command: str, *, timeout: float = 15.0):
    """Send execute frame and return batch_complete JSON."""
    payload = base64.b64encode(command.encode("utf-8")).decode("ascii")
    await communicator.send_json_to({"type": "execute", "data": payload})

    batch_complete = None
    for _ in range(int(timeout * 4)):
        response = await communicator.receive_json_from(timeout=timeout)
        if response["type"] == "batch_started":
            continue
        if response["type"] == "batch_complete":
            batch_complete = response
            break
    assert batch_complete is not None, "timed out waiting for batch_complete"
    return batch_complete


@pytest.mark.django_db
def test_terminal_create_and_list(workspace_client, workspace):
    resp = workspace_client.post("/api/terminals/", {}, format="json")
    assert resp.status_code == 201
    tid = resp.json()["id"]

    resp = workspace_client.get("/api/terminals/")
    assert resp.status_code == 200
    ids = [t["id"] for t in resp.json()]
    assert tid in ids


@pytest.mark.django_db
def test_terminal_exec(workspace_client, workspace, exposed_root):
    resp = workspace_client.post("/api/terminals/", {}, format="json")
    tid = resp.json()["id"]
    resp = workspace_client.post(
        f"/api/terminals/{tid}/exec/",
        {"command": "echo hello"},
        format="json",
    )
    assert resp.status_code == 200
    assert "stdout" in resp.json()


@pytest.mark.django_db
def test_terminal_delete(workspace_client):
    resp = workspace_client.post("/api/terminals/", {}, format="json")
    tid = resp.json()["id"]
    resp = workspace_client.delete(f"/api/terminals/{tid}/")
    assert resp.status_code == 204
    terminal = Terminal.objects.get(id=tid)
    assert terminal.status == TerminalStatus.CLOSED


@pytest.mark.django_db
def test_close_stale_terminals(registered_device, workspace):
    terminal = Terminal.objects.create(
        device=registered_device,
        workspace=workspace,
        name="stale",
        shell="powershell",
        cwd=workspace.absolute_path,
        status=TerminalStatus.ACTIVE,
        pid=9999,
    )
    Terminal.objects.filter(id=terminal.id).update(
        last_used=timezone.now() - timedelta(hours=2)
    )
    terminal.refresh_from_db()

    closed = close_stale_terminals(device=registered_device, workspace_id=workspace.id)
    assert closed == 1
    terminal.refresh_from_db()
    assert terminal.status == TerminalStatus.CLOSED
    assert terminal.pid is None


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_terminal_ws_attach(api_key, registered_device, workspace, device_hash, terminal):
    url = (
        f"/api/ws/terminals/{terminal.id}/?"
        f"api_key={api_key}&device_hash={device_hash}&workspace_id={workspace.id}"
    )
    communicator = WebsocketCommunicator(application, url)
    connected, _ = await communicator.connect()
    assert connected

    response = await communicator.receive_json_from(timeout=5)
    assert response["type"] == "ready"
    assert response["shell"] == "powershell"

    response = await communicator.receive_json_from(timeout=5)
    assert response["type"] == "attached"

    response = await communicator.receive_json_from(timeout=5)
    assert response["type"] == "output_full"

    await communicator.disconnect()


@pytest.mark.skipif(sys.platform != "win32", reason="Windows interactive shells only")
@pytest.mark.skipif(not _HAS_PYWINPTY, reason="pywinpty not installed")
@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_terminal_ws_execute_real_cmd(
    api_key,
    registered_device,
    workspace,
    device_hash,
    monkeypatch,
):
    """End-to-end: WS auth with project API_KEY, execute echo, assert visible output."""
    monkeypatch.delenv("TERMINAL_PTY_BACKEND", raising=False)

    terminal = await _create_cmd_terminal(registered_device, workspace)
    url = (
        f"/api/ws/terminals/{terminal.id}/?"
        f"api_key={api_key}&device_hash={device_hash}&workspace_id={workspace.id}"
    )
    communicator = WebsocketCommunicator(application, url)
    connected, _ = await communicator.connect()
    assert connected

    await _ws_attach(communicator)

    batch_complete = await _ws_execute_and_collect(
        communicator,
        "echo jacksheet\n",
    )

    assert batch_complete["exit_code"] == 0
    assert batch_complete.get("data"), "batch_complete missing raw data"

    raw = base64.b64decode(batch_complete["data"])
    assert b"jacksheet" in raw, f"raw PTY missing token: {raw!r}"

    text = batch_complete.get("text") or format_terminal_stdout(
        raw, "echo jacksheet"
    )
    assert "jacksheet" in text, f"display text missing token: {text!r}"

    await communicator.disconnect()


async def _create_cmd_terminal(registered_device, workspace):
    from channels.db import database_sync_to_async

    @database_sync_to_async
    def _create():
        return Terminal.objects.create(
            device=registered_device,
            workspace=workspace,
            name="cmd-integration",
            shell="cmd",
            cwd=workspace.absolute_path,
            cols=80,
            rows=24,
            status=TerminalStatus.ACTIVE,
        )

    return await _create()


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_terminal_ws_io_persisted(
    api_key, registered_device, workspace, device_hash, terminal, monkeypatch
):
    monkeypatch.setenv("TERMINAL_PTY_BACKEND", "fake")
    url = (
        f"/api/ws/terminals/{terminal.id}/?"
        f"api_key={api_key}&device_hash={device_hash}&workspace_id={workspace.id}"
    )
    communicator = WebsocketCommunicator(application, url)
    connected, _ = await communicator.connect()
    assert connected

    response = await communicator.receive_json_from(timeout=5)
    assert response["type"] == "ready"

    response = await communicator.receive_json_from(timeout=5)
    assert response["type"] == "attached"

    response = await communicator.receive_json_from(timeout=5)
    assert response["type"] == "output_full"

    await communicator.send_json_to(
        {"type": "execute", "data": base64.b64encode(b"echo test\r\n").decode("ascii")}
    )

    got_output = False
    for _ in range(20):
        response = await communicator.receive_json_from(timeout=5)
        if response["type"] == "batch_started":
            continue
        if response["type"] in ("output", "output_full") and response.get("data"):
            got_output = True
        if response["type"] == "batch_complete":
            if response.get("data"):
                got_output = True
            break
    assert got_output

    await communicator.disconnect()

    from channels.db import database_sync_to_async
    from terminals.models import TerminalIO, TerminalIODirection

    @database_sync_to_async
    def _io_exists():
        return (
            TerminalIO.objects.filter(
                terminal=terminal, direction=TerminalIODirection.INPUT
            ).exists(),
            TerminalIO.objects.filter(
                terminal=terminal, direction=TerminalIODirection.OUTPUT
            ).exists(),
        )

    has_input, has_output = await _io_exists()
    assert has_input
    assert has_output


@pytest.mark.django_db
def test_terminal_io_list(workspace_client, terminal):
    from terminals.models import TerminalIO, TerminalIODirection

    TerminalIO.objects.create(
        terminal=terminal,
        direction=TerminalIODirection.OUTPUT,
        data="aGVsbG8=",
    )
    resp = workspace_client.get(f"/api/terminals/{terminal.id}/io/")
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 1
    assert body[0]["direction"] == "output"
    assert body[0]["data"] == "aGVsbG8="


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_terminal_ws_closed_after_idle(
    api_key, registered_device, workspace, device_hash, closed_terminal
):
    url = (
        f"/api/ws/terminals/{closed_terminal.id}/?"
        f"api_key={api_key}&device_hash={device_hash}&workspace_id={workspace.id}"
    )
    communicator = WebsocketCommunicator(application, url)
    connected, _ = await communicator.connect()
    assert connected

    response = await communicator.receive_json_from(timeout=5)
    assert response["type"] == "error"
    assert response["code"] == "terminal_closed"

    await communicator.disconnect()
