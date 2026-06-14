"""WebSocket tests for watchdog, ide_search, getbypath, git."""

import pytest
from channels.testing.websocket import WebsocketCommunicator

from config.asgi import application


def _ws_url(path: str, api_key: str, device_hash: str, workspace_id: int | None = None) -> str:
    qs = f"api_key={api_key}&device_hash={device_hash}"
    if workspace_id is not None:
        qs += f"&workspace_id={workspace_id}"
    return f"/api/ws/{path}?{qs}"


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_watchdog_connects(api_key, registered_device, device_hash):
    url = _ws_url("watchdog/", api_key, device_hash)
    communicator = WebsocketCommunicator(application, url)
    connected, _ = await communicator.connect()
    assert connected
    await communicator.disconnect()


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_ide_search_ws(api_key, registered_device, device_hash, workspace, exposed_root):
    (exposed_root / "findme.txt").write_text("hello world", encoding="utf-8")
    url = _ws_url("ide_search/", api_key, device_hash, workspace.id)
    communicator = WebsocketCommunicator(application, url)
    connected, _ = await communicator.connect()
    assert connected

    await communicator.send_json_to(
        {
            "type": "search",
            "workspace_id": workspace.id,
            "keyword": "hello",
            "match_case": False,
            "match_exact": False,
        }
    )
    started = await communicator.receive_json_from()
    assert started["type"] == "search_started"

    results = []
    while True:
        msg = await communicator.receive_json_from(timeout=5)
        if msg["type"] == "search_result":
            results.append(msg["result"])
            continue
        assert msg["type"] == "search_complete"
        break
    assert msg["count"] >= 1
    assert len(results) >= 1
    assert any(r.get("asset") for r in results)
    await communicator.disconnect()


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_ide_search_ws_spaced_phrase(
    api_key, registered_device, device_hash, workspace, exposed_root
):
    (exposed_root / "phrase.txt").write_text("say hello world today\n", encoding="utf-8")
    url = _ws_url("ide_search/", api_key, device_hash, workspace.id)
    communicator = WebsocketCommunicator(application, url)
    connected, _ = await communicator.connect()
    assert connected

    await communicator.send_json_to(
        {
            "type": "search",
            "workspace_id": workspace.id,
            "keyword": "hello world",
            "match_case": False,
            "match_exact": False,
        }
    )
    await communicator.receive_json_from()
    results = []
    while True:
        msg = await communicator.receive_json_from(timeout=5)
        if msg["type"] == "search_result":
            results.append(msg["result"])
            continue
        assert msg["type"] == "search_complete"
        break
    assert msg["count"] == 1
    assert len(results) == 1
    assert results[0]["text"] == "say hello world today"
    await communicator.disconnect()


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_getbypath_ws(api_key, registered_device, device_hash, workspace, exposed_root):
    sample = exposed_root / "sample.txt"
    sample.write_text("line one\nline two\n", encoding="utf-8")
    url = _ws_url("getbypath/", api_key, device_hash, workspace.id)
    communicator = WebsocketCommunicator(application, url)
    connected, _ = await communicator.connect()
    assert connected

    await communicator.send_json_to(
        {
            "type": "get",
            "workspace_id": workspace.id,
            "path": str(sample),
        }
    )
    started = await communicator.receive_json_from()
    assert started["type"] == "file_started"
    assert started["asset"] == "sample.txt"
    assert started["is_text"] is True

    content = ""
    while True:
        msg = await communicator.receive_json_from()
        if msg["type"] == "file_complete":
            break
        if msg["type"] == "chunk":
            content += msg["content"]
    assert "line one" in content
    await communicator.disconnect()


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_getbypath_rejects_missing_file(api_key, registered_device, device_hash, workspace):
    url = _ws_url("getbypath/", api_key, device_hash, workspace.id)
    communicator = WebsocketCommunicator(application, url)
    connected, _ = await communicator.connect()
    assert connected

    await communicator.send_json_to(
        {
            "type": "get",
            "workspace_id": workspace.id,
            "path": "missing-file.txt",
        }
    )
    msg = await communicator.receive_json_from()
    assert msg["type"] == "error"
    assert msg["code"] == "file_not_found"
    await communicator.disconnect()


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_git_status_ws(api_key, registered_device, device_hash, workspace):
    url = _ws_url("git/", api_key, device_hash, workspace.id)
    communicator = WebsocketCommunicator(application, url)
    connected, _ = await communicator.connect()
    assert connected

    await communicator.send_json_to({"type": "status", "workspace_id": workspace.id})
    msg = await communicator.receive_json_from()
    assert msg["type"] == "status"
    assert "files" in msg
    await communicator.disconnect()
