import pytest

from core.models import Workspace


@pytest.mark.django_db
def test_list_workspaces(api_client, workspace):
    resp = api_client.get("/api/workspaces/")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 1
    assert data[0]["id"] == workspace.id


@pytest.mark.django_db
def test_create_workspace(api_client, exposed_root):
    resp = api_client.post(
        "/api/workspaces/",
        {"absolute_path": str(exposed_root)},
        format="json",
    )
    assert resp.status_code == 201
    assert resp.json()["absolute_path"] == str(exposed_root.resolve())


@pytest.mark.django_db
def test_create_workspace_rejects_outside(api_client, tmp_path, settings):
    outside = tmp_path / "outside"
    outside.mkdir()
    resp = api_client.post(
        "/api/workspaces/",
        {"absolute_path": str(outside)},
        format="json",
    )
    assert resp.status_code == 403
    assert resp.json()["code"] == "path_not_allowed"


@pytest.mark.django_db
def test_patch_workspace(api_client, workspace):
    resp = api_client.patch(
        f"/api/workspaces/{workspace.id}/",
        {"label": "Renamed"},
        format="json",
    )
    assert resp.status_code == 200
    assert resp.json()["label"] == "Renamed"


@pytest.mark.django_db
def test_delete_workspace_soft(api_client, workspace):
    resp = api_client.delete(f"/api/workspaces/{workspace.id}/")
    assert resp.status_code == 204
    workspace.refresh_from_db()
    assert workspace.is_active is False


@pytest.mark.django_db
def test_bind_cursor_stub(api_client, workspace, settings):
    settings.CURSOR_API_KEY = ""
    resp = api_client.post(f"/api/workspaces/{workspace.id}/bind-cursor/")
    assert resp.status_code == 503
