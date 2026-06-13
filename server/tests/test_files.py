import base64

import pytest


@pytest.mark.django_db
def test_files_roots(api_client, exposed_root):
    resp = api_client.get("/api/files/roots/")
    assert resp.status_code == 200
    roots = resp.json()
    assert any(r["full_path"] == str(exposed_root.resolve()) for r in roots)


@pytest.mark.django_db
def test_files_by_path_directory(api_client, exposed_root):
    (exposed_root / "subdir").mkdir()
    resp = api_client.get("/api/files/by-path/", {"path": str(exposed_root)})
    assert resp.status_code == 200
    data = resp.json()
    assert data["type"] == "directory"
    names = [c["name"] for c in data["children"]]
    assert "subdir" in names


@pytest.mark.django_db
def test_files_touch_and_by_path_file(api_client, exposed_root):
    resp = api_client.post(
        "/api/files/touch/",
        {"path": str(exposed_root), "name": "hello.txt"},
        format="json",
    )
    assert resp.status_code == 201
    file_path = resp.json()["path"]
    resp = api_client.get("/api/files/by-path/", {"path": file_path})
    assert resp.status_code == 200
    data = resp.json()
    assert data["type"] == "file"
    content = base64.b64decode(data["content_base64"]).decode()
    assert content == ""


@pytest.mark.django_db
def test_files_mkdir(api_client, exposed_root):
    resp = api_client.post(
        "/api/files/mkdir/",
        {"path": str(exposed_root), "name": "newdir"},
        format="json",
    )
    assert resp.status_code == 201
    assert (exposed_root / "newdir").is_dir()


@pytest.mark.django_db
def test_workspace_sync(workspace_client, workspace, exposed_root):
    (exposed_root / "a.txt").write_text("hi")
    resp = workspace_client.post(f"/api/workspaces/{workspace.id}/sync/")
    assert resp.status_code == 200
    tree = resp.json()
    assert tree["type"] == "directory"
    child_names = [c["name"] for c in tree["children"]]
    assert "a.txt" in child_names


@pytest.mark.django_db
def test_search_files(workspace_client, workspace, exposed_root):
    (exposed_root / "findme.py").write_text("x = 1")
    resp = workspace_client.get(
        "/api/search/files/",
        {"q": "findme", "workspace_id": workspace.id},
    )
    assert resp.status_code == 200
    results = resp.json()
    assert any("findme" in r["name"] for r in results)


@pytest.mark.django_db
def test_search_grep(workspace_client, workspace, exposed_root):
    (exposed_root / "code.py").write_text("def hello():\n    return 42\n")
    resp = workspace_client.post(
        "/api/search/grep/",
        {
            "pattern": "hello",
            "workspace_id": workspace.id,
            "case_sensitive": False,
        },
        format="json",
    )
    assert resp.status_code == 200
    results = resp.json()
    assert len(results) >= 1
