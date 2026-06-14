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
def test_workspace_sync_metadata_only(workspace_client, workspace, exposed_root):
    (exposed_root / "a.txt").write_text("hello")
    resp = workspace_client.post(f"/api/workspaces/{workspace.id}/sync/")
    assert resp.status_code == 200
    tree = resp.json()
    assert tree["type"] == "directory"
    child_names = [c["name"] for c in tree["children"]]
    assert "a.txt" in child_names

    file_node = next(c for c in tree["children"] if c["name"] == "a.txt")
    assert file_node["sync_policy"] == "inline"
    assert "content_base64" not in file_node
    assert tree["sync_summary"]["inline_count"] == 1


@pytest.mark.django_db
def test_workspace_sync_include_content(workspace_client, workspace, exposed_root):
    (exposed_root / "a.txt").write_text("hello")
    resp = workspace_client.post(
        f"/api/workspaces/{workspace.id}/sync/?include_content=true",
    )
    assert resp.status_code == 200
    file_node = next(c for c in resp.json()["children"] if c["name"] == "a.txt")
    assert "content_base64" in file_node
    assert base64.b64decode(file_node["content_base64"]).decode() == "hello"


@pytest.mark.django_db
def test_workspace_sync_files_batch(workspace_client, workspace, exposed_root):
    (exposed_root / "a.txt").write_text("alpha")
    (exposed_root / "b.txt").write_text("beta")
    file_a = str((exposed_root / "a.txt").resolve())
    file_b = str((exposed_root / "b.txt").resolve())

    resp = workspace_client.post(
        f"/api/workspaces/{workspace.id}/sync/files/",
        {"paths": [file_a, file_b]},
        format="json",
    )
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["files"]) == 2
    payloads = {item["path"]: item for item in data["files"]}
    assert base64.b64decode(payloads[file_a]["content_base64"]).decode() == "alpha"
    assert base64.b64decode(payloads[file_b]["content_base64"]).decode() == "beta"


@pytest.mark.django_db
def test_workspace_sync_files_rejects_outside_workspace(
    workspace_client, workspace, exposed_root, tmp_path, settings
):
    outside = tmp_path / "outside.txt"
    outside.write_text("nope")
    settings.EXPOSED_DIRECTORIES_ABSOLUTE_PATHS.append(str(tmp_path))

    resp = workspace_client.post(
        f"/api/workspaces/{workspace.id}/sync/files/",
        {"paths": [str(outside.resolve())]},
        format="json",
    )
    assert resp.status_code == 200
    assert resp.json()["files"] == []
    assert resp.json()["skipped"][0]["code"] == "path_not_allowed"


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


@pytest.mark.django_db
def test_search_grep_spaced_phrase(workspace_client, workspace, exposed_root):
    (exposed_root / "notes.txt").write_text("say hello world here\n", encoding="utf-8")
    resp = workspace_client.post(
        "/api/search/grep/",
        {
            "pattern": "hello world",
            "workspace_id": workspace.id,
            "case_sensitive": False,
        },
        format="json",
    )
    assert resp.status_code == 200
    results = resp.json()
    assert len(results) == 1
    assert results[0]["matches"][0]["text"] == "say hello world here"


@pytest.mark.django_db
def test_search_grep_whole_word(workspace_client, workspace, exposed_root):
    (exposed_root / "words.txt").write_text("hello helloworld\n", encoding="utf-8")
    resp = workspace_client.post(
        "/api/search/grep/",
        {
            "pattern": "hello",
            "workspace_id": workspace.id,
            "case_sensitive": False,
            "whole_word": True,
        },
        format="json",
    )
    assert resp.status_code == 200
    results = resp.json()
    assert len(results) == 1
    assert results[0]["matches"][0]["text"] == "hello helloworld"
