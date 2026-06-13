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
