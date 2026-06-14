"""Resolve and stream workspace files by path."""

from __future__ import annotations

import base64
import mimetypes
from collections.abc import Iterator
from pathlib import Path

_TEXT_SUFFIXES = {
    ".py", ".dart", ".js", ".ts", ".tsx", ".jsx", ".json", ".md", ".txt", ".yaml", ".yml",
    ".html", ".css", ".scss", ".sql", ".sh", ".bat", ".ps1", ".toml", ".ini", ".cfg",
    ".xml", ".csv", ".rs", ".go", ".java", ".kt", ".c", ".cpp", ".h", ".hpp", ".cs",
    ".rb", ".php", ".swift", ".m", ".mm", ".vue", ".svelte", ".gradle", ".properties",
}
_MAX_FILE_BYTES = 10 * 1024 * 1024  # 10 MB
_CHUNK_CHARS = 64 * 1024  # UTF-8 text chunks (~64 KiB)
_CHUNK_BYTES = 256 * 1024  # binary chunks


def _asset_name(path: Path) -> str:
    return path.name or str(path)


def _looks_textual(path: Path) -> bool:
    if path.suffix.lower() in _TEXT_SUFFIXES:
        return True
    return path.suffix == ""


def resolve_workspace_file(root: Path, path: str) -> Path | None:
    """Return an absolute file path under [root], or None if invalid."""
    root_resolved = root.resolve()
    candidate = Path(path)
    if not candidate.is_absolute():
        candidate = root_resolved / candidate
    try:
        resolved = candidate.resolve(strict=False)
        resolved.relative_to(root_resolved)
    except (ValueError, OSError):
        return None
    if not resolved.is_file():
        return None
    return resolved


def file_meta(path: Path) -> dict:
    stat = path.stat()
    is_text = _looks_textual(path)
    mime, _ = mimetypes.guess_type(path.name)
    return {
        "path": str(path),
        "asset": _asset_name(path),
        "size": stat.st_size,
        "is_text": is_text,
        "mime_type": mime or ("text/plain" if is_text else "application/octet-stream"),
    }


def stream_workspace_file(path: Path) -> Iterator[dict]:
    """Yield chunk dicts for a validated workspace file."""
    size = path.stat().st_size
    if size > _MAX_FILE_BYTES:
        raise ValueError(f"File exceeds {_MAX_FILE_BYTES} byte limit")

    is_text = _looks_textual(path)
    if is_text:
        text = path.read_text(encoding="utf-8", errors="replace")
        for index in range(0, len(text), _CHUNK_CHARS):
            yield {
                "index": index // _CHUNK_CHARS,
                "encoding": "utf-8",
                "content": text[index : index + _CHUNK_CHARS],
            }
        return

    data = path.read_bytes()
    for index, offset in enumerate(range(0, len(data), _CHUNK_BYTES)):
        chunk = data[offset : offset + _CHUNK_BYTES]
        yield {
            "index": index,
            "encoding": "base64",
            "content": base64.b64encode(chunk).decode("ascii"),
        }
