from django.db import models

from core.models import DeviceIdentifier, Workspace


class TerminalStatus(models.TextChoices):
    ACTIVE = "active", "Active"
    CLOSED = "closed", "Closed"


class Terminal(models.Model):
    device = models.ForeignKey(DeviceIdentifier, on_delete=models.CASCADE)
    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE)
    name = models.CharField(max_length=128)
    shell = models.CharField(max_length=32, default="powershell")
    cwd = models.TextField()
    cols = models.PositiveSmallIntegerField(default=80)
    rows = models.PositiveSmallIntegerField(default=24)
    pid = models.IntegerField(null=True, blank=True)
    status = models.CharField(
        max_length=16, choices=TerminalStatus.choices, default=TerminalStatus.ACTIVE
    )
    last_used = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.name} ({self.status})"


class TerminalIODirection(models.TextChoices):
    INPUT = "input", "Input"
    OUTPUT = "output", "Output"


class TerminalIO(models.Model):
    """Persisted terminal stream chunks (like AgentMessage for sessions)."""

    terminal = models.ForeignKey(
        Terminal, on_delete=models.CASCADE, related_name="io_lines"
    )
    direction = models.CharField(max_length=8, choices=TerminalIODirection.choices)
    data = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]
        indexes = [
            models.Index(fields=["terminal", "created_at"]),
        ]

    def __str__(self):
        return f"{self.direction}@{self.created_at}"
