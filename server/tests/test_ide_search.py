"""Unit tests for Aho-Corasick IDE search."""

from pathlib import Path

import pytest

from ide.search_service import _build_automaton, _line_matches, stream_ide_search


def test_line_matches_substring():
    automaton = _build_automaton("hello", match_case=False)
    hits = _line_matches("say Hello world", automaton, match_case=False)
    assert hits == [(4, 9)]


def test_line_matches_case_sensitive():
    automaton = _build_automaton("Hello", match_case=True)
    assert _line_matches("say Hello world", automaton, match_case=True) == [(4, 9)]
    assert _line_matches("say hello world", automaton, match_case=True) == []


def test_stream_ide_search_finds_keyword(tmp_path):
    root = tmp_path / "project"
    root.mkdir()
    (root / "main.py").write_text("def hello():\n    print('hello world')\n", encoding="utf-8")
    (root / "skip.bin").write_bytes(b"\x00\x01hello")

    results = list(
        stream_ide_search(
            root,
            keyword="hello",
            match_case=False,
            match_exact=False,
        )
    )
    assert len(results) == 1
    assert results[0]["asset"] == "main.py"
    assert len(results[0]["matches"]) >= 2
    assert results[0]["matches"][0]["start_index"] >= 0


def test_stream_ide_search_respects_include_glob(tmp_path):
    root = tmp_path / "project"
    root.mkdir()
    (root / "a.py").write_text("needle here", encoding="utf-8")
    (root / "b.txt").write_text("needle there", encoding="utf-8")

    results = list(
        stream_ide_search(
            root,
            keyword="needle",
            files_to_include=["*.py"],
        )
    )
    assert len(results) == 1
    assert results[0]["asset"] == "a.py"
