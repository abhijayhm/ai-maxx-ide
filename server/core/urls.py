from django.urls import include, path

from core import views as core_views

urlpatterns = [
    path("health/", core_views.health_view, name="health"),
    path("devices/register/", core_views.device_register_view, name="device-register"),
    path(
        "devices/identifier/",
        core_views.device_identifier_view,
        name="device-identifier",
    ),
    path("workspaces/", core_views.workspace_list_create_view, name="workspace-list"),
    path(
        "workspaces/<int:workspace_id>/",
        core_views.workspace_detail_view,
        name="workspace-detail",
    ),
    path(
        "workspaces/<int:workspace_id>/bind-cursor/",
        core_views.workspace_bind_cursor_view,
        name="workspace-bind-cursor",
    ),
    path("workspaces/<int:workspace_id>/sync/", include("files.urls_sync")),
]
