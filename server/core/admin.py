from django.contrib import admin

from core.models import AgentMessage, DeviceIdentifier, Workspace


@admin.register(DeviceIdentifier)
class DeviceIdentifierAdmin(admin.ModelAdmin):
    list_display = ("hash", "label", "is_active", "created_at", "last_seen_at")
    list_filter = ("is_active",)
    search_fields = ("hash", "label")


@admin.register(Workspace)
class WorkspaceAdmin(admin.ModelAdmin):
    list_display = ("label", "absolute_path", "device", "is_active", "cursor_agent_id")
    list_filter = ("is_active",)
    search_fields = ("label", "absolute_path", "cursor_agent_id")


@admin.register(AgentMessage)
class AgentMessageAdmin(admin.ModelAdmin):
    list_display = ("timestamp", "sender", "receiver", "device", "workspace", "run_id")
    list_filter = ("sender", "receiver")
    search_fields = ("run_id",)
