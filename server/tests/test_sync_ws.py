import base64

import pytest
from channels.testing.websocket import WebsocketCommunicator

from config.asgi import application


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_sync_ws_metadata_and_files(
    api_key, registered_device, workspace, device_hash, exposed_root
):
    (exposed_root / "a.txt").write_text("alpha")
    (exposed_root / "b.txt").write_text("beta")

    url = (
        f"/api/ws/sync/{workspace.id}/?"
        f"api_key={api_key}&device_hash={device_hash}&workspace_id={workspace.id}"
    )
    communicator = WebsocketCommunicator(application, url)
    connected, _ = await communicator.connect()
    assert connected

    ready = await communicator.receive_json_from(timeout=5)
    assert ready["type"] == "ready"

    await communicator.send_json_to({"type": "start"})

    started = await communicator.receive_json_from(timeout=5)
    assert started["type"] == "sync_started"

    saw_metadata = False
    saw_files = False
    saw_complete = False

    for _ in range(20):
        msg = await communicator.receive_json_from(timeout=10)
        if msg["type"] == "metadata":
            saw_metadata = True
            assert msg["files_total"] == 2
            child_names = [c["name"] for c in msg["tree"]["children"]]
            assert "a.txt" in child_names
        elif msg["type"] == "files":
            saw_files = True
            assert msg["files_done"] <= msg["files_total"]
            payloads = {item["path"]: item for item in msg["files"]}
            for path in payloads:
                assert base64.b64decode(payloads[path]["content_base64"]).decode() in {
                    "alpha",
                    "beta",
                }
        elif msg["type"] == "complete":
            saw_complete = True
            break
        elif msg["type"] == "bind_cursor":
            continue

    assert saw_metadata
    assert saw_files
    assert saw_complete

    await communicator.disconnect()


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_sync_ws_rejects_unauthenticated(workspace):
    url = f"/api/ws/sync/{workspace.id}/"
    communicator = WebsocketCommunicator(application, url)
    connected, _ = await communicator.connect()
    assert not connected
