from django.contrib import admin

from terminals.models import Terminal, TerminalIO


class TerminalIOInline(admin.TabularInline):
    model = TerminalIO
    extra = 0
    readonly_fields = ("direction", "data", "created_at")


@admin.register(Terminal)
class TerminalAdmin(admin.ModelAdmin):
    list_display = ("name", "shell", "device", "workspace", "status", "pid", "last_used")
    list_filter = ("status", "shell")
    inlines = [TerminalIOInline]


@admin.register(TerminalIO)
class TerminalIOAdmin(admin.ModelAdmin):
    list_display = ("terminal", "direction", "created_at")
    list_filter = ("direction",)
