"""REST + route tree tests for the slim IDE API."""

from pathlib import Path

import pytest

from ide.route_tree import build_exposed_routes_tree, build_workspace_tree, flatten_tree, list_directory_nodes


def test_exposed_routes_tree_returns_roots(api_client, exposed_root):
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
    assert root["path"] == str(exposed_root)
    assert root["path_type"] == "folder"
    assert root["children"] == []

    nested = api_client.get("/api/exposed_routes_tree/", {"path": str(exposed_root)})
    assert nested.status_code == 200
    nested_assets = {item["asset"] for item in nested.json()}
    assert nested_assets == {"alpha.txt", "sub"}

    deeper = api_client.get("/api/exposed_routes_tree/", {"path": str(sub)})
    assert deeper.status_code == 200
    assert {item["asset"] for item in deeper.json()} == {"beta.txt"}


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


def test_workspace_tree_full_sync(workspace_client, workspace, exposed_root):
    sub = Path(workspace.absolute_path) / "pkg"
    sub.mkdir()
    (sub / "inner.py").write_text("x", encoding="utf-8")
    (Path(workspace.absolute_path) / "main.py").write_text("print()", encoding="utf-8")

    response = workspace_client.get(f"/api/workspaces/{workspace.id}/tree/")
    assert response.status_code == 200
    tree = response.json()
    assert tree["path_type"] == "folder"
    flat = flatten_tree([tree])
    assets = {item["asset"] for item in flat}
    assert assets == {Path(workspace.absolute_path).name, "main.py", "pkg", "inner.py"}


def test_list_directory_nodes_includes_files_and_folders(tmp_path):
    root = tmp_path / "root"
    root.mkdir()
    (root / "a.txt").write_text("a", encoding="utf-8")
    (root / "dir").mkdir()
    nodes = list_directory_nodes(root)
    assert {n["asset"] for n in nodes} == {"a.txt", "dir"}
    assert {n["path_type"] for n in nodes} == {"file", "folder"}
