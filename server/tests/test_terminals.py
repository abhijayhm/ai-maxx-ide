import base64
import json
from datetime import timedelta

import pytest
from channels.testing.websocket import WebsocketCommunicator
from django.utils import timezone

from config.asgi import application
from terminals.models import Terminal, TerminalStatus
from terminals.pty_manager import PtyManager
from terminals.services import close_stale_terminals


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
    assert response["type"] == "attached"
    assert response["shell"] == "powershell"

    response = await communicator.receive_json_from(timeout=5)
    assert response["type"] == "output_full"

    await communicator.disconnect()


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
    assert response["type"] == "attached"

    response = await communicator.receive_json_from(timeout=5)
    assert response["type"] == "output_full"

    await communicator.send_json_to(
        {"type": "input", "data": base64.b64encode(b"echo test\r\n").decode("ascii")}
    )

    got_output = False
    for _ in range(20):
        response = await communicator.receive_json_from(timeout=5)
        if response["type"] == "output_full" and response.get("data"):
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
