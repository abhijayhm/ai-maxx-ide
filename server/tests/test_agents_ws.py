import pytest
from channels.testing.websocket import WebsocketCommunicator

from config.asgi import application


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_agent_ws_auth_and_message(api_key, registered_device, workspace, device_hash):
    url = (
        f"/api/ws/agent/?api_key={api_key}&device_hash={device_hash}&workspace_id={workspace.id}"
    )
    communicator = WebsocketCommunicator(application, url)
    connected, _ = await communicator.connect()
    assert connected

    await communicator.send_json_to({"type": "message", "text": "Hello agent"})
    saw_stream = False
    for _ in range(10):
        response = await communicator.receive_json_from(timeout=5)
        if response.get("type") == "stream":
            saw_stream = True
            break
    assert saw_stream

    await communicator.disconnect()


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_agent_ws_auth_frame(api_key, registered_device, workspace, device_hash):
    communicator = WebsocketCommunicator(application, "/api/ws/agent/")
    connected, _ = await communicator.connect()
    assert connected

    await communicator.send_json_to(
        {
            "type": "auth",
            "api_key": api_key,
            "device_hash": device_hash,
            "workspace_id": workspace.id,
        }
    )
    response = await communicator.receive_json_from(timeout=5)
    assert response["type"] == "auth_ok"

    await communicator.send_json_to({"type": "message", "text": "test"})
    response = await communicator.receive_json_from(timeout=5)
    assert response.get("type") in ("stream", "run_started", "error")

    await communicator.disconnect()


@pytest.mark.django_db
def test_agent_messages_http(workspace_client, workspace, registered_device):
    from core.models import AgentMessage, Sender

    AgentMessage.objects.create(
        device=registered_device,
        workspace=workspace,
        sender=Sender.USER,
        receiver=Sender.SYSTEM,
        run_id="r1",
        payload={"text": "hi"},
    )
    resp = workspace_client.get("/api/agent/messages/")
    assert resp.status_code == 200
    assert len(resp.json()) == 1


@pytest.mark.django_db
def test_agent_status(workspace_client):
    resp = workspace_client.get("/api/agent/status/")
    assert resp.status_code == 200
    assert resp.json()["running"] is False
