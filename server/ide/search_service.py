"""Streaming VS Code-style search via ripgrep."""

from __future__ import annotations

import json
import re
import subprocess
from collections.abc import Iterator
from pathlib import Path


def _asset_name(path: Path) -> str:
    return path.name or str(path)


def _parse_include_exclude(
    files_to_include: list | str | None,
    files_to_exclude: list | str | None,
) -> tuple[list[str], list[str]]:
    include = files_to_include if isinstance(files_to_include, list) else []
    exclude = files_to_exclude if isinstance(files_to_exclude, list) else []
    return include, exclude


def stream_ide_search(
    root: Path,
    *,
    keyword: str,
    match_case: bool = False,
    match_exact: bool = False,
    files_to_include: list | str | None = None,
    files_to_exclude: list | str | None = None,
) -> Iterator[dict]:
    """Yield per-file result objects as matches are found."""
    if not keyword:
        return

    pattern = re.escape(keyword) if match_exact else keyword
    include, exclude = _parse_include_exclude(files_to_include, files_to_exclude)

    cmd = ["rg", "--json", "--line-number", pattern, str(root)]
    if not match_case:
        cmd.insert(1, "-i")
    if match_exact:
        cmd.insert(1, "-F")
    for glob in include:
        if glob:
            cmd.extend(["--glob", glob])
    for glob in exclude:
        if glob:
            cmd.extend(["--glob", f"!{glob}"])

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
    except FileNotFoundError:
        yield from _fallback_search(
            root,
            keyword=keyword,
            match_case=match_case,
            match_exact=match_exact,
        )
        return

    grouped: dict[str, list[dict]] = {}
    try:
        assert proc.stdout is not None
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if obj.get("type") != "match":
                continue
            data = obj.get("data", {})
            path_text = data.get("path", {}).get("text", "")
            line_num = data.get("line_number", 0)
            line_text = data.get("lines", {}).get("text", "").rstrip("\n")
            submatches = data.get("submatches") or []
            if submatches:
                sm = submatches[0]
                start_index = sm.get("start", 0)
                end_index = sm.get("end", start_index + len(keyword))
            else:
                start_index = 0
                end_index = len(keyword)

            abs_path = Path(path_text)
            try:
                rel = abs_path.relative_to(root)
                display_path = str(abs_path)
            except ValueError:
                display_path = path_text
                rel = Path(path_text)

            match_obj = {
                "line": line_num,
                "start_index": start_index,
                "end_index": end_index,
                "text": line_text,
            }
            key = display_path
            if key not in grouped:
                grouped[key] = []
            grouped[key].append(match_obj)

            yield {
                "path": display_path,
                "asset": _asset_name(abs_path if abs_path.is_absolute() else root / rel),
                "matches": list(grouped[key]),
            }
    finally:
        proc.wait(timeout=60)

    if proc.returncode not in (0, 1) and not grouped:
        yield from _fallback_search(
            root,
            keyword=keyword,
            match_case=match_case,
            match_exact=match_exact,
        )


def _fallback_search(
    root: Path,
    *,
    keyword: str,
    match_case: bool,
    match_exact: bool,
) -> Iterator[dict]:
    flags = 0 if match_case else re.IGNORECASE
    if match_exact:
        regex = re.compile(re.escape(keyword), flags)
    else:
        regex = re.compile(keyword, flags)

    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        matches = []
        for i, line in enumerate(text.splitlines(), start=1):
            m = regex.search(line)
            if not m:
                continue
            matches.append(
                {
                    "line": i,
                    "start_index": m.start(),
                    "end_index": m.end(),
                    "text": line,
                }
            )
        if matches:
            yield {
                "path": str(path),
                "asset": _asset_name(path),
                "matches": matches,
            }
