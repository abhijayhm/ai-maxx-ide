import subprocess

import pytest

from gitapp.runner import GitRunner, set_runner_override


@pytest.mark.django_db
def test_git_status(workspace_client, workspace):
    def mock_runner(args, timeout=60):
        return subprocess.CompletedProcess(
            args=["git"] + args,
            returncode=0,
            stdout=" M file.txt\n",
            stderr="",
        )

    set_runner_override(mock_runner)
    try:
        resp = workspace_client.get("/api/git/status/")
        assert resp.status_code == 200
        files = resp.json()["files"]
        assert len(files) == 1
        assert files[0]["path"] == "file.txt"
    finally:
        set_runner_override(None)


@pytest.mark.django_db
def test_git_stage(workspace_client):
    calls = []

    def mock_runner(args, timeout=60):
        calls.append(args)
        return subprocess.CompletedProcess(args=["git"] + args, returncode=0, stdout="", stderr="")

    set_runner_override(mock_runner)
    try:
        resp = workspace_client.post(
            "/api/git/stage/",
            {"paths": ["a.txt"]},
            format="json",
        )
        assert resp.status_code == 200
        assert calls[0][0] == "add"
    finally:
        set_runner_override(None)


@pytest.mark.django_db
def test_git_branches(workspace_client):
    def mock_runner(args, timeout=60):
        return subprocess.CompletedProcess(
            args=["git"] + args,
            returncode=0,
            stdout="* main\n  dev\n",
            stderr="",
        )

    set_runner_override(mock_runner)
    try:
        resp = workspace_client.get("/api/git/branches/")
        assert resp.status_code == 200
        data = resp.json()
        assert data["current"] == "main"
        assert "dev" in data["branches"]
    finally:
        set_runner_override(None)


@pytest.mark.django_db
def test_git_exec_disallowed(workspace_client):
    resp = workspace_client.post(
        "/api/git/exec/",
        {"command": ["clean", "-fd"]},
        format="json",
    )
    assert resp.status_code == 400


def test_git_runner_unit(tmp_path):
    def mock_runner(args, timeout=60):
        return subprocess.CompletedProcess(args=["git"] + args, returncode=0, stdout="", stderr="")

    runner = GitRunner(str(tmp_path), runner=mock_runner)
    proc = runner.add(["x.txt"])
    assert proc.returncode == 0
