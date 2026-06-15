"""Route tree nodes: path, asset, path_type, children."""

from __future__ import annotations

import os
from pathlib import Path

from core.utils.paths import get_exposed_roots

_SKIP_DIR_NAMES = {".git", "__pycache__", "node_modules", ".dart_tool", "build"}


def _asset_name(path: Path) -> str:
    name = path.name
    if name:
        return name
    return str(path).rstrip("\\/").split(os.sep)[-1] or str(path)


def node_for_path(path: Path, *, max_depth: int | None = None, depth: int = 0) -> dict:
    """Build a single route tree node (recursive for directories)."""
    asset = _asset_name(path)
    if path.is_dir():
        children: list[dict] = []
        if max_depth is None or depth < max_depth:
            try:
                entries = sorted(
                    path.iterdir(),
                    key=lambda p: (not p.is_dir(), p.name.lower()),
                )
            except (OSError, PermissionError):
                entries = []
            for entry in entries:
                if entry.is_symlink():
                    continue
                if not entry.is_dir():
                    continue
                if entry.name in _SKIP_DIR_NAMES:
                    continue
                children.append(
                    node_for_path(entry, max_depth=max_depth, depth=depth + 1)
                )
        return {
            "path": str(path),
            "asset": asset,
            "path_type": "folder",
            "children": children,
        }

    return {
        "path": str(path),
        "asset": asset,
        "path_type": "file",
        "children": [],
    }


def build_exposed_routes_tree() -> list[dict]:
    """One tree node per configured exposed root."""
    return [node_for_path(root) for root in get_exposed_roots()]


def build_workspace_tree(workspace_root: Path) -> dict:
    root = workspace_root.resolve()
    if not root.is_dir():
        raise NotADirectoryError(str(root))
    return node_for_path(root)


def flatten_tree(nodes: list[dict] | dict) -> list[dict]:
    """Depth-first flatten; each item omits children."""
    if isinstance(nodes, dict):
        nodes = [nodes]

    flat: list[dict] = []

    def walk(node: dict) -> None:
        flat.append(
            {
                "path": node["path"],
                "asset": node["asset"],
                "path_type": node["path_type"],
            }
        )
        for child in node.get("children") or []:
            walk(child)

    for root in nodes:
        walk(root)
    return flat
