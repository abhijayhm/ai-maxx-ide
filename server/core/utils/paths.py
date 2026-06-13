"""Path sandbox utilities."""

import os
from pathlib import Path

from django.conf import settings


def _normalize_root(path: str | Path) -> Path:
    return Path(path).resolve()


def get_exposed_roots() -> list[Path]:
    return [_normalize_root(p) for p in settings.EXPOSED_DIRECTORIES_ABSOLUTE_PATHS]


def _paths_equal(a: Path, b: Path) -> bool:
    if os.name == "nt":
        return str(a).lower() == str(b).lower()
    return a == b


def is_under_exposed_roots(path: Path) -> bool:
    """Return True if resolved path is under any exposed root."""
    try:
        resolved = path.resolve()
    except (OSError, ValueError):
        return False
    for root in get_exposed_roots():
        try:
            resolved.relative_to(root)
            return True
        except ValueError:
            if os.name == "nt":
                resolved_str = str(resolved).lower()
                root_str = str(root).lower()
                if resolved_str == root_str or resolved_str.startswith(root_str + os.sep):
                    return True
    return False


class PathNotAllowedError(Exception):
    def __init__(self, detail: str = "Path is outside exposed directories."):
        self.code = "path_not_allowed"
        self.detail = detail
        super().__init__(detail)


def resolve_allowed_path(requested: str) -> Path:
    """Raise PathNotAllowedError if not under EXPOSED_DIRECTORIES_ABSOLUTE_PATHS."""
    if not requested or not str(requested).strip():
        raise PathNotAllowedError("Path is required.")

    candidate = Path(requested)
    if not candidate.is_absolute():
        raise PathNotAllowedError("Path must be absolute.")

    try:
        resolved = candidate.resolve()
    except (OSError, ValueError) as exc:
        raise PathNotAllowedError(str(exc)) from exc

    if ".." in Path(requested).parts:
        raise PathNotAllowedError("Path traversal is not allowed.")

    if not is_under_exposed_roots(resolved):
        raise PathNotAllowedError("Path is outside exposed directories.")

    return resolved
