"""File tree building utilities."""

import base64
import os
from datetime import datetime, timezone
from pathlib import Path

from django.conf import settings

from core.utils.paths import get_exposed_roots


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


def is_within_workspace(path: Path, workspace_root: Path) -> bool:
    try:
        path.resolve().relative_to(workspace_root.resolve())
        return True
    except ValueError:
        return False


def inline_sync_policy(size: int) -> str:
    if size <= settings.FILE_SYNC_INLINE_MAX_BYTES:
        return "inline"
    return "metadata_only"


def build_sync_tree(path: Path, *, include_content: bool = False) -> dict:
    """Build workspace sync tree.

    Phase 1 (default): metadata JSON only — no embedded file bodies.
    Phase 2: client fetches inline bodies via ``POST .../sync/files/``.
    """
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
        node["sync_policy"] = inline_sync_policy(size)
        if include_content and node["sync_policy"] == "inline":
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
            node["children"].append(build_sync_tree(entry, include_content=include_content))
        else:
            node["children"].append(build_sync_tree(entry, include_content=include_content))
    return node


def attach_sync_summary(node: dict) -> dict:
    """Attach roll-up counts on the workspace root for client progress UI."""
    summary = {
        "total_nodes": 0,
        "file_count": 0,
        "inline_count": 0,
        "metadata_only_count": 0,
    }

    def walk(item: dict) -> None:
        summary["total_nodes"] += 1
        if item.get("type") == "file":
            summary["file_count"] += 1
            if item.get("sync_policy") == "inline":
                summary["inline_count"] += 1
            else:
                summary["metadata_only_count"] += 1
        for child in item.get("children", []):
            walk(child)

    walk(node)
    node["sync_summary"] = summary
    return node


def read_sync_file_entry(path: Path) -> dict:
    """File payload for background sync phase 2."""
    stat = path.stat()
    policy = inline_sync_policy(stat.st_size)
    entry = {
        "type": "file",
        "path": str(path),
        "size": stat.st_size,
        "modified_at": _stat_modified(path),
        "sync_policy": policy,
    }
    if policy == "inline":
        entry["content_base64"] = base64.b64encode(path.read_bytes()).decode("ascii")
    return entry


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
