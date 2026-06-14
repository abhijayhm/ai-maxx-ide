"""Persist and replay terminal IO lines."""

from channels.db import database_sync_to_async

from terminals.models import Terminal, TerminalIO, TerminalIODirection


@database_sync_to_async
def save_terminal_io(terminal_id: int, direction: str, data_b64: str) -> TerminalIO:
    return TerminalIO.objects.create(
        terminal_id=terminal_id,
        direction=direction,
        data=data_b64,
    )


@database_sync_to_async
def list_terminal_io(terminal_id: int, *, limit: int = 500, offset: int = 0):
    return list(
        TerminalIO.objects.filter(terminal_id=terminal_id)
        .order_by("created_at")[offset : offset + limit]
    )


@database_sync_to_async
def replay_output_text(terminal_id: int) -> str:
    """Concatenate persisted output chunks for terminal display bootstrap."""
    parts: list[str] = []
    for line in TerminalIO.objects.filter(
        terminal_id=terminal_id,
        direction=TerminalIODirection.OUTPUT,
    ).order_by("created_at"):
        if line.data:
            parts.append(line.data)
    return "".join(parts)
