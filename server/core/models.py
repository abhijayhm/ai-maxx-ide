from pathlib import Path

from django.db import models


class DeviceIdentifier(models.Model):
    hash = models.CharField(max_length=64, unique=True, db_index=True)
    data = models.JSONField()
    label = models.CharField(max_length=128, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    last_seen_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.label or self.hash[:12]


class Workspace(models.Model):
    absolute_path = models.TextField()
    device = models.ForeignKey(
        DeviceIdentifier, on_delete=models.CASCADE, related_name="workspaces"
    )
    label = models.CharField(max_length=255, blank=True)
    cursor_agent_id = models.CharField(max_length=128, blank=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return Path(self.absolute_path).name or self.absolute_path


class Sender(models.TextChoices):
    USER = "user", "User"
    SYSTEM = "system", "System"


class AgentMessage(models.Model):
    timestamp = models.DateTimeField(auto_now_add=True)
    sender = models.CharField(max_length=16, choices=Sender.choices)
    receiver = models.CharField(max_length=16, choices=Sender.choices)
    device = models.ForeignKey(DeviceIdentifier, on_delete=models.CASCADE)
    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE)
    run_id = models.CharField(max_length=64, blank=True)
    payload = models.JSONField()

    class Meta:
        ordering = ["-timestamp"]

    def __str__(self):
        return f"{self.sender}->{self.receiver} @ {self.timestamp}"
