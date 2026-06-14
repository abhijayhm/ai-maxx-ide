import os

from django.apps import AppConfig


class IdeConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "ide"

    def ready(self):
        if os.environ.get("IDE_WATCHDOG_ENABLED", "true").lower() == "false":
            return
        from ide.watchdog_service import exposed_watchdog

        exposed_watchdog.ensure_started()
