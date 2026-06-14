"""REST + route tree tests for the slim IDE API."""

from pathlib import Path

import pytest

from ide.route_tree import build_exposed_routes_tree, flatten_tree, node_for_path


def test_exposed_routes_tree(api_client, exposed_root):
    (exposed_root / "alpha.txt").write_text("a", encoding="utf-8")
    sub = exposed_root / "sub"
    sub.mkdir()
    (sub / "beta.txt").write_text("b", encoding="utf-8")

    response = api_client.get("/api/exposed_routes_tree/")
    assert response.status_code == 200
    data = response.json()
    assert isinstance(data, list)
    assert len(data) == 1
    root = data[0]
    assert root["path_type"] == "folder"
    assert root["asset"]
    flat = flatten_tree(data)
    paths = {item["path"] for item in flat}
    assert str(exposed_root / "alpha.txt") in paths


def test_workspace_open_creates(api_client, exposed_root):
    response = api_client.post("/api/workspaces/", {"path": str(exposed_root)}, format="json")
    assert response.status_code == 201
    body = response.json()
    assert body["id"]
    assert body["path"] == str(exposed_root)
    assert body["created"] is True

    again = api_client.post("/api/workspaces/", {"path": str(exposed_root)}, format="json")
    assert again.status_code == 200
    assert again.json()["created"] is False


def test_workspace_open_rejects_file(api_client, exposed_root):
    file_path = exposed_root / "only.txt"
    file_path.write_text("x", encoding="utf-8")
    response = api_client.post("/api/workspaces/", {"path": str(file_path)}, format="json")
    assert response.status_code == 400


def test_workspace_tree(workspace_client, workspace, exposed_root):
    (Path(workspace.absolute_path) / "main.py").write_text("print()", encoding="utf-8")
    response = workspace_client.get(f"/api/workspaces/{workspace.id}/tree/")
    assert response.status_code == 200
    tree = response.json()
    assert tree["path_type"] == "folder"
    flat = flatten_tree([tree])
    assert any(item["asset"] == "main.py" for item in flat)
