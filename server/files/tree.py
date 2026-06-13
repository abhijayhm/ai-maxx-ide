"""File tree building utilities."""

import base64
import os
from datetime import datetime, timezone
from pathlib import Path

from django.conf import settings

from core.utils.paths import get_exposed_roots, resolve_allowed_path


def list_roots():
    roots = []
    for root in get_exposed_roots():
        roots.append(
            {
                "full_path": str(root),
                "folder_name": root.name or str(root),
            }
        )
    return roots


def _stat_modified(path: Path) -> str:
    mtime = path.stat().st_mtime
    return datetime.fromtimestamp(mtime, tz=timezone.utc).isoformat()


def _entry_for_path(path: Path) -> dict:
    if path.is_dir():
        return {
            "name": path.name,
            "path": str(path),
            "type": "directory",
            "size": 0,
            "modified_at": _stat_modified(path),
        }
    stat = path.stat()
    return {
        "name": path.name,
        "path": str(path),
        "type": "file",
        "size": stat.st_size,
        "modified_at": _stat_modified(path),
    }


def list_directory(path: Path) -> dict:
    children = []
    try:
        entries = sorted(path.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower()))
    except PermissionError:
        entries = []
    for entry in entries:
        if entry.is_symlink():
            continue
        children.append(_entry_for_path(entry))
    return {
        "type": "directory",
        "path": str(path),
        "children": children,
    }


def read_file_entry(path: Path) -> dict:
    stat = path.stat()
    content = path.read_bytes()
    return {
        "type": "file",
        "path": str(path),
        "size": stat.st_size,
        "content_base64": base64.b64encode(content).decode("ascii"),
    }


def build_sync_tree(path: Path) -> dict:
    node = {
        "path": str(path),
        "name": path.name or str(path),
        "type": "directory" if path.is_dir() else "file",
        "children": [],
        "size": 0,
        "modified_at": _stat_modified(path),
        "sync_policy": "metadata_only",
    }

    if path.is_file():
        size = path.stat().st_size
        node["size"] = size
        node["sync_policy"] = (
            "inline" if size <= settings.FILE_SYNC_INLINE_MAX_BYTES else "metadata_only"
        )
        if node["sync_policy"] == "inline":
            node["content_base64"] = base64.b64encode(path.read_bytes()).decode("ascii")
        return node

    try:
        entries = sorted(path.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower()))
    except PermissionError:
        entries = []

    for entry in entries:
        if entry.is_symlink():
            continue
        if entry.is_dir():
            node["children"].append(build_sync_tree(entry))
        else:
            child = build_sync_tree(entry)
            node["children"].append(child)
    return node


def search_files(workspace_path: Path, query: str, limit: int = 50) -> list[dict]:
    results = []
    query_lower = query.lower()

    for root, dirs, files in os.walk(workspace_path):
        dirs[:] = [d for d in dirs if not (Path(root) / d).is_symlink()]
        for name in files:
            if query_lower in name.lower():
                full = Path(root) / name
                results.append({"name": name, "path": str(full)})
                if len(results) >= limit:
                    return results
    return results
