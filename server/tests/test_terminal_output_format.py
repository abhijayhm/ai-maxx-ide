"""Tests for terminal output cleaning."""

from terminals.output_format import format_terminal_stdout, sanitize_terminal_output


def test_sanitize_strips_csi():
    raw = b"\x1b[4;37Hhello\x1b[4;42H"
    assert sanitize_terminal_output(raw) == "hello"


def test_format_echo_jacksheet():
    raw = (
        b"\x1b[4;38Hecho jacksheet\x1b[4;52H\r\n"
        b"jacksheet\r\n"
        b"C:\\workspace>"
    )
    assert format_terminal_stdout(raw, "echo jacksheet") == "jacksheet"


def test_format_cmd_not_recognized():
    raw = b"'hello' is not recognized as an internal or external command,\r\noperable program or batch file.\r\n"
    assert "not recognized" in format_terminal_stdout(raw, "hello")
