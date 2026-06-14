"""Clean PTY bytes into plain text for terminal response bubbles."""

from __future__ import annotations

import re

_CSI = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")
_OSC = re.compile(r"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)")
_DEC = re.compile(r"\x1B[()][A-Z0-9]|\x1B[>=]")
_PROMPT = re.compile(
    r"^(PS [^\n>]+>\s*|>>\s*|(?:[A-Za-z]:)?\\[^\n>]*>\s*|>\s*)$"
)


def sanitize_terminal_output(raw: bytes | str) -> str:
    text = raw.decode("utf-8", errors="replace") if isinstance(raw, bytes) else raw
    text = _CSI.sub("", text)
    text = _OSC.sub("", text)
    text = _DEC.sub("", text)
    text = text.replace("\x07", "").replace("\x00", "")
    return text.replace("\r\n", "\n").replace("\r", "\n")


def format_terminal_stdout(raw: bytes | str, command: str) -> str:
    text = sanitize_terminal_output(raw)
    if not text:
        return ""

    cmd = command.strip()
    if cmd:
        for prefix in (cmd, f"{cmd}\n", f"{cmd}\r\n"):
            if text.startswith(prefix):
                text = text[len(prefix) :]
                break

    lines = text.split("\n")

    while lines and not lines[0].strip():
        lines.pop(0)

    while lines:
        first = lines[0].strip()
        if not first:
            lines.pop(0)
            continue
        if cmd and _line_matches_command(first, cmd):
            lines.pop(0)
            continue
        break

    while lines:
        last = lines[-1].strip()
        if not last or _PROMPT.match(last):
            lines.pop()
            continue
        break

    cleaned = "\n".join(lines).strip()
    if cleaned:
        return cleaned

    # Inline cmd editing sometimes leaves only the typed token after CSI strip.
    bare = sanitize_terminal_output(raw).strip()
    if cmd and bare.lower() == cmd.lower():
        return ""

    return bare


def _line_matches_command(line: str, command: str) -> bool:
    return line == command or line.lower() == command.lower()
