import pytest
from channels.testing.websocket import WebsocketCommunicator

from config.asgi import application
from core.models import AgentSession


@pytest.fixture(autouse=True)
def stub_cursor_agent(settings, monkeypatch):
    settings.CURSOR_API_KEY = ""
    monkeypatch.setattr("agents.cursor_bridge.RAISE_ERROR", False)


@pytest.fixture
def agent_session(db, workspace, registered_device):
    return AgentSession.objects.create(
        workspace=workspace,
        device=registered_device,
    )


@pytest.mark.django_db(transaction=True)
@pytest.mark.asyncio
async def test_agent_ws_auth_and_message(
    api_key, registered_device, workspace, device_hash, agent_session
):
    url = (
        f"/api/ws/agent/?api_key={api_key}&device_hash={device_hash}&workspace_id={workspace.id}"
    )
    communicator = WebsocketCommunicator(application, url)
    connected, _ = await communicator.connect()
    assert connected

    await communicator.send_json_to(
        {
            "type": "message",
            "text": "Hello agent",
            "session_id": agent_session.id,
        }
    )
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
async def test_agent_ws_auth_frame(
    api_key, registered_device, workspace, device_hash, agent_session
):
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

    await communicator.send_json_to(
        {"type": "message", "text": "test", "session_id": agent_session.id}
    )
    response = await communicator.receive_json_from(timeout=5)
    assert response.get("type") in ("stream", "run_started", "error")

    await communicator.disconnect()


@pytest.mark.django_db
def test_agent_sessions_list_and_create(workspace_client, workspace, registered_device):
    resp = workspace_client.get("/api/agent/sessions/")
    assert resp.status_code == 200
    assert resp.json() == []

    resp = workspace_client.post("/api/agent/sessions/")
    assert resp.status_code == 201
    body = resp.json()
    assert "id" in body
    assert "created_at" in body
    assert AgentSession.objects.filter(workspace=workspace).count() == 1


@pytest.mark.django_db
def test_agent_messages_http(workspace_client, workspace, registered_device, agent_session):
    from core.models import AgentMessage, Sender

    AgentMessage.objects.create(
        device=registered_device,
        workspace=workspace,
        agent_session=agent_session,
        sender=Sender.USER,
        receiver=Sender.SYSTEM,
        run_id="r1",
        payload={"text": "hi"},
    )
    AgentMessage.objects.create(
        device=registered_device,
        workspace=workspace,
        sender=Sender.USER,
        receiver=Sender.SYSTEM,
        run_id="r2",
        payload={"text": "other session"},
    )
    resp = workspace_client.get("/api/agent/messages/")
    assert resp.status_code == 200
    assert len(resp.json()) == 2

    resp = workspace_client.get(
        f"/api/agent/messages/?session_id={agent_session.id}"
    )
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 1
    assert body[0]["payload"]["text"] == "hi"
    assert body[0]["agent_session"] == agent_session.id


@pytest.mark.django_db
def test_agent_models(workspace_client):
    resp = workspace_client.get("/api/agent/models/")
    assert resp.status_code == 200
    body = resp.json()
    assert isinstance(body, list)
    assert len(body) >= 1
    assert "id" in body[0]


@pytest.mark.django_db
def test_agent_status(workspace_client):
    resp = workspace_client.get("/api/agent/status/")
    assert resp.status_code == 200
    assert resp.json()["running"] is False
