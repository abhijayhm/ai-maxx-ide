from django.urls import include, path

from core import views as core_views
from ide import views as ide_views

urlpatterns = [
    path("health/", core_views.health_view, name="health"),
    path("devices/register/", core_views.device_register_view, name="device-register"),
    path(
        "devices/identifier/",
        core_views.device_identifier_view,
        name="device-identifier",
    ),
    path(
        "exposed_routes_tree/",
        ide_views.exposed_routes_tree_view,
        name="exposed-routes-tree",
    ),
    path("workspaces/", ide_views.workspace_open_view, name="workspace-open"),
    path(
        "workspaces/<int:workspace_id>/tree/",
        ide_views.workspace_tree_view,
        name="workspace-tree",
    ),
    path("", include("agents.urls")),
    path("", include("terminals.urls")),
]
