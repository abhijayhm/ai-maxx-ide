"""Unit tests for workspace file resolution and streaming."""

from pathlib import Path

import pytest

from ide.file_service import file_meta, resolve_workspace_file, stream_workspace_file


def test_resolve_workspace_file_accepts_absolute_path(tmp_path):
    root = tmp_path / "ws"
    root.mkdir()
    sample = root / "a.txt"
    sample.write_text("hello", encoding="utf-8")

    resolved = resolve_workspace_file(root, str(sample))
    assert resolved == sample.resolve()


def test_resolve_workspace_file_rejects_outside_root(tmp_path):
    root = tmp_path / "ws"
    root.mkdir()
    outside = tmp_path / "outside.txt"
    outside.write_text("nope", encoding="utf-8")

    assert resolve_workspace_file(root, str(outside)) is None


def test_stream_workspace_file_text_chunks(tmp_path):
    root = tmp_path / "ws"
    root.mkdir()
    sample = root / "a.txt"
    sample.write_text("alpha\nbeta\n", encoding="utf-8")

    chunks = list(stream_workspace_file(sample))
    assert chunks
    assert "".join(chunk["content"] for chunk in chunks) == "alpha\nbeta\n"
    meta = file_meta(sample)
    assert meta["is_text"] is True
