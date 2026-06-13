"""Validate common/urls.json against Django URL routing."""

import json
from pathlib import Path

import pytest
from django.urls import resolve, Resolver404

REPO_ROOT = Path(__file__).resolve().parents[2]
URLS_JSON = REPO_ROOT / "common" / "urls.json"


@pytest.fixture(scope="module")
def urls_config():
    with URLS_JSON.open(encoding="utf-8") as handle:
        return json.load(handle)


def _django_path(api_path: str) -> str:
    """Map manifest path to Django resolve path (/api/ prefix)."""
    return f"/api/{api_path}"


def _fill_params(path: str) -> str:
    return (
        path.replace("{workspace_id}", "1")
        .replace("{session_id}", "1")
        .replace("{terminal_id}", "1")
    )


@pytest.mark.parametrize(
    "key",
    [
        "health",
        "workspaces_list",
        "files_roots",
        "git_status",
        "terminals_list",
        "agent_status",
        "search_files",
    ],
)
def test_rest_paths_resolve(urls_config, key):
    entry = urls_config["rest"][key]
    django_path = _django_path(_fill_params(entry["path"]))
    try:
        resolve(django_path)
    except Resolver404 as exc:
        pytest.fail(f"{key} → {django_path} did not resolve: {exc}")


def test_urls_json_structure(urls_config):
    assert urls_config["api_base_path"] == "/api/"
    assert urls_config["ws_base_path"] == "/api/ws/"
    assert "agent" in urls_config["websocket"]
    assert "sync" in urls_config["websocket"]
    assert len(urls_config["rest"]) >= 20


def test_ws_paths_in_routing(urls_config):
    from config.routing import websocket_urlpatterns

    registered = {route.pattern._route for route in websocket_urlpatterns}
    for name, entry in urls_config["websocket"].items():
        expected = f"api/ws/{entry['path']}".rstrip("/") + "/"
        expected = expected.replace("{workspace_id}", "<int:workspace_id>").replace(
            "{session_id}", "<int:session_id>"
        ).replace("{terminal_id}", "<int:terminal_id>")
        assert expected in registered, f"WS route missing for {name}: {expected}"
