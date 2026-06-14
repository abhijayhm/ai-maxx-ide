import pytest
from channels.testing.websocket import WebsocketCommunicator

from config.asgi import application
from remote.input_executor import clear_executed, clear_staging, get_staging


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_remote_ws_auth_and_input(api_key, registered_device, device_hash):
    clear_staging()
    clear_executed()

    url = f"/api/ws/remote/?api_key={api_key}&device_hash={device_hash}"
    communicator = WebsocketCommunicator(application, url)
    connected, _ = await communicator.connect()
    assert connected

    response = await communicator.receive_json_from(timeout=5)
    assert response["type"] == "auth_ok"

    await communicator.send_json_to(
        {
            "type": "input_batch",
            "events": [{"op": "key_combo", "keys": ["ctrl", "c"]}],
            "dispatch": False,
        }
    )
    response = await communicator.receive_json_from(timeout=5)
    assert response["type"] == "input_staged"
    assert len(get_staging()) == 1

    await communicator.send_json_to(
        {
            "type": "input_batch",
            "events": [],
            "dispatch": True,
        }
    )
    response = await communicator.receive_json_from(timeout=5)
    assert response["type"] == "input_executed"
    assert response["count"] >= 1

    await communicator.disconnect()


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_remote_ws_signaling(api_key, registered_device, device_hash):
    url = f"/api/ws/remote/?api_key={api_key}&device_hash={device_hash}"
    communicator = WebsocketCommunicator(application, url)
    connected, _ = await communicator.connect()
    assert connected

    response = await communicator.receive_json_from(timeout=5)
    assert response["type"] == "auth_ok"

    await communicator.send_json_to({"type": "offer", "sdp": "fake-sdp"})
    response = await communicator.receive_json_from(timeout=5)
    assert response["type"] == "answer"

    response = await communicator.receive_json_from(timeout=5)
    assert response["type"] == "connected"

    await communicator.disconnect()
