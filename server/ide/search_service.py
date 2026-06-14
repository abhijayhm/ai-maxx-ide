"""Streaming VS Code-style search via Aho-Corasick (pyahocorasick)."""

from __future__ import annotations

import fnmatch
from collections.abc import Iterator
from pathlib import Path

import ahocorasick

_SKIP_DIR_NAMES = {".git", "__pycache__", "node_modules", ".dart_tool", "build", ".venv", "venv"}
_MAX_FILE_BYTES = 2 * 1024 * 1024  # 2 MB per file
_TEXT_SUFFIXES = {
    ".py", ".dart", ".js", ".ts", ".tsx", ".jsx", ".json", ".md", ".txt", ".yaml", ".yml",
    ".html", ".css", ".scss", ".sql", ".sh", ".bat", ".ps1", ".toml", ".ini", ".cfg",
    ".xml", ".csv", ".rs", ".go", ".java", ".kt", ".c", ".cpp", ".h", ".hpp", ".cs",
}


def _asset_name(path: Path) -> str:
    return path.name or str(path)


def _parse_include_exclude(
    files_to_include: list | str | None,
    files_to_exclude: list | str | None,
) -> tuple[list[str], list[str]]:
    include = files_to_include if isinstance(files_to_include, list) else []
    exclude = files_to_exclude if isinstance(files_to_exclude, list) else []
    return include, exclude


def _build_automaton(keyword: str, *, match_case: bool) -> ahocorasick.Automaton:
    """Build an Aho-Corasick automaton for a single search keyword."""
    automaton = ahocorasick.Automaton()
    needle = keyword if match_case else keyword.casefold()
    automaton.add_word(needle, (needle, len(keyword)))
    automaton.make_automaton()
    return automaton


def _line_matches(
    line: str,
    automaton: ahocorasick.Automaton,
    *,
    match_case: bool,
) -> list[tuple[int, int]]:
    """Return (start_index, end_index) pairs for substring matches on one line."""
    haystack = line if match_case else line.casefold()
    hits: list[tuple[int, int]] = []
    for end_index, (_needle, orig_len) in automaton.iter(haystack):
        start_index = end_index - orig_len + 1
        hits.append((start_index, end_index + 1))
    return hits


def _path_matches_globs(
    path: Path,
    root: Path,
    include: list[str],
    exclude: list[str],
) -> bool:
    rel = path.relative_to(root).as_posix()
    name = path.name
    if include and not any(
        fnmatch.fnmatch(rel, pattern) or fnmatch.fnmatch(name, pattern) for pattern in include
    ):
        return False
    if exclude and any(
        fnmatch.fnmatch(rel, pattern) or fnmatch.fnmatch(name, pattern) for pattern in exclude
    ):
        return False
    return True


def _looks_textual(path: Path) -> bool:
    if path.suffix.lower() in _TEXT_SUFFIXES:
        return True
    return path.suffix == ""


def _iter_search_files(
    root: Path,
    *,
    include: list[str],
    exclude: list[str],
) -> Iterator[Path]:
    stack = [root]
    while stack:
        current = stack.pop()
        try:
            entries = list(current.iterdir())
        except (OSError, PermissionError):
            continue
        for entry in sorted(entries, key=lambda p: p.name.lower()):
            if entry.is_symlink():
                continue
            if entry.is_dir():
                if entry.name in _SKIP_DIR_NAMES:
                    continue
                stack.append(entry)
                continue
            if not entry.is_file():
                continue
            if not _path_matches_globs(entry, root, include, exclude):
                continue
            if not _looks_textual(entry):
                continue
            try:
                if entry.stat().st_size > _MAX_FILE_BYTES:
                    continue
            except OSError:
                continue
            yield entry


def stream_ide_search(
    root: Path,
    *,
    keyword: str,
    match_case: bool = False,
    match_exact: bool = False,  # noqa: ARG001 — reserved; AC search is always literal
    files_to_include: list | str | None = None,
    files_to_exclude: list | str | None = None,
) -> Iterator[dict]:
    """Yield per-file result objects as matches are found."""
    trimmed = keyword.strip()
    if not trimmed:
        return

    include, exclude = _parse_include_exclude(files_to_include, files_to_exclude)
    automaton = _build_automaton(trimmed, match_case=match_case)

    for path in _iter_search_files(root, include=include, exclude=exclude):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue

        file_matches: list[dict] = []
        for line_no, line in enumerate(text.splitlines(), start=1):
            for start_index, end_index in _line_matches(
                line,
                automaton,
                match_case=match_case,
            ):
                file_matches.append(
                    {
                        "line": line_no,
                        "start_index": start_index,
                        "end_index": end_index,
                        "text": line,
                    }
                )

        if file_matches:
            display_path = str(path)
            yield {
                "path": display_path,
                "asset": _asset_name(path),
                "matches": file_matches,
            }
