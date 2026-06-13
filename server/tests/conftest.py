"""Shared pytest fixtures."""

import pytest
from rest_framework.test import APIClient

from core.models import DeviceIdentifier, Workspace
from core.utils.hashing import compute_device_hash
from terminals.models import Terminal, TerminalStatus


@pytest.fixture
def exposed_root(tmp_path, settings):
    root = tmp_path / "workspace"
    root.mkdir()
    settings.EXPOSED_DIRECTORIES_ABSOLUTE_PATHS = [str(root)]
    return root


@pytest.fixture
def api_key(settings):
    return settings.API_KEY


@pytest.fixture
def device_data():
    return {"platform": "test", "device_id": "test-device-001"}


@pytest.fixture
def device_hash(device_data):
    return compute_device_hash(device_data)


@pytest.fixture
def registered_device(db, device_data, device_hash):
    return DeviceIdentifier.objects.create(
        hash=device_hash,
        data=device_data,
        is_active=True,
    )


@pytest.fixture
def workspace(db, registered_device, exposed_root):
    return Workspace.objects.create(
        device=registered_device,
        absolute_path=str(exposed_root),
        label="workspace",
        is_active=True,
    )


@pytest.fixture
def api_client(api_key, registered_device, device_hash):
    client = APIClient()
    client.credentials(
        HTTP_X_API_KEY=api_key,
        HTTP_X_DEVICE_IDENTIFIER=device_hash,
    )
    return client


@pytest.fixture
def workspace_client(api_client, workspace):
    api_client.credentials(
        HTTP_X_API_KEY=api_client._credentials.get("HTTP_X_API_KEY"),
        HTTP_X_DEVICE_IDENTIFIER=api_client._credentials.get("HTTP_X_DEVICE_IDENTIFIER"),
        HTTP_X_WORKSPACE_ID=str(workspace.id),
    )
    return api_client


@pytest.fixture
def terminal(db, registered_device, workspace):
    return Terminal.objects.create(
        device=registered_device,
        workspace=workspace,
        name="ws-test",
        shell="powershell",
        cwd=workspace.absolute_path,
        status=TerminalStatus.ACTIVE,
    )


@pytest.fixture
def closed_terminal(db, registered_device, workspace):
    return Terminal.objects.create(
        device=registered_device,
        workspace=workspace,
        name="closed",
        shell="powershell",
        cwd=workspace.absolute_path,
        status=TerminalStatus.CLOSED,
    )


@pytest.fixture(autouse=True)
def fake_pty_backend(monkeypatch):
    monkeypatch.setenv("TERMINAL_PTY_BACKEND", "fake")
