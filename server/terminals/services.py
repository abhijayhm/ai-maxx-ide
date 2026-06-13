"""Terminal idle cleanup service."""

from django.conf import settings
from django.utils import timezone

from terminals.models import Terminal, TerminalStatus
from terminals.pty_manager import PtyManager


def close_stale_terminals(*, device, workspace_id: int | None = None) -> int:
    cutoff = timezone.now() - settings.TERMINAL_IDLE_TTL
    qs = Terminal.objects.filter(
        device=device,
        status=TerminalStatus.ACTIVE,
        last_used__lt=cutoff,
    )
    if workspace_id is not None:
        qs = qs.filter(workspace_id=workspace_id)

    closed = 0
    for terminal in qs:
        PtyManager.kill(terminal.pid)
        terminal.pid = None
        terminal.status = TerminalStatus.CLOSED
        terminal.save(update_fields=["pid", "status"])
        closed += 1
    return closed
