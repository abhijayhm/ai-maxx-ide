from django.contrib import admin

from terminals.models import Terminal


@admin.register(Terminal)
class TerminalAdmin(admin.ModelAdmin):
    list_display = ("name", "shell", "device", "workspace", "status", "pid", "last_used")
    list_filter = ("status", "shell")
