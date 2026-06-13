"""Shared workspace sync logic for REST and WebSocket transports."""

from pathlib import Path

from django.conf import settings

from core.utils.paths import PathNotAllowedError, resolve_allowed_path
from files.tree import (
    attach_sync_summary,
    build_sync_tree,
    is_within_workspace,
    read_sync_file_entry,
)


def build_workspace_sync_tree(workspace) -> dict:
    root = Path(workspace.absolute_path)
    if not root.exists():
        raise FileNotFoundError("Workspace path not found.")
    tree = build_sync_tree(root, include_content=False)
    return attach_sync_summary(tree)


def collect_inline_paths(node: dict) -> list[str]:
    paths: list[str] = []

    def walk(item: dict) -> None:
        if item.get("type") == "file" and item.get("sync_policy") == "inline":
            paths.append(item["path"])
        for child in item.get("children", []):
            walk(child)

    walk(node)
    return paths


def fetch_sync_file_batch(workspace_root: Path, paths: list[str]) -> tuple[list[dict], list[dict]]:
    files: list[dict] = []
    skipped: list[dict] = []

    for raw_path in paths:
        if not isinstance(raw_path, str) or not raw_path.strip():
            skipped.append(
                {
                    "path": raw_path,
                    "code": "invalid_path",
                    "message": "Path must be a non-empty string.",
                }
            )
            continue

        try:
            path = resolve_allowed_path(raw_path)
        except PathNotAllowedError as exc:
            skipped.append(
                {
                    "path": raw_path,
                    "code": "path_not_allowed",
                    "message": exc.detail,
                }
            )
            continue

        if not is_within_workspace(path, workspace_root):
            skipped.append(
                {
                    "path": raw_path,
                    "code": "path_not_allowed",
                    "message": "Path is outside the active workspace.",
                }
            )
            continue

        if not path.is_file():
            skipped.append(
                {
                    "path": raw_path,
                    "code": "not_a_file",
                    "message": "Path is not a file.",
                }
            )
            continue

        if path.stat().st_size > settings.FILE_SYNC_INLINE_MAX_BYTES:
            skipped.append(
                {
                    "path": raw_path,
                    "code": "too_large",
                    "message": "File exceeds inline sync size limit.",
                }
            )
            continue

        files.append(read_sync_file_entry(path))

    return files, skipped
