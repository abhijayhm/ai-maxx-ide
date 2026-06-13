"""DRF permission classes."""

from rest_framework.permissions import BasePermission

from core.models import Workspace


class IsRegisteredDevice(BasePermission):
    """Require authenticated device from DeviceAPIKeyAuthentication."""

    def has_permission(self, request, view):
        return getattr(request, "user", None) is not None or getattr(
            request, "auth", None
        ) is not None


class RequiresWorkspace(BasePermission):
    """Require valid X-Workspace-Id header belonging to the device."""

    message = "Workspace required."

    def has_permission(self, request, view):
        device = request.user
        if device is None:
            return False

        workspace_id = request.headers.get("X-Workspace-Id") or request.query_params.get(
            "workspace_id"
        )
        if not workspace_id:
            return False

        try:
            workspace = Workspace.objects.get(
                id=int(workspace_id), device=device, is_active=True
            )
        except (Workspace.DoesNotExist, ValueError, TypeError):
            return False

        request.workspace = workspace
        return True


def get_workspace_from_request(request):
    """Resolve workspace from header, query, or request attribute."""
    if hasattr(request, "workspace"):
        return request.workspace

    device = request.user
    workspace_id = request.headers.get("X-Workspace-Id") or request.query_params.get(
        "workspace_id"
    )
    if not workspace_id or device is None:
        return None

    try:
        return Workspace.objects.get(id=int(workspace_id), device=device, is_active=True)
    except (Workspace.DoesNotExist, ValueError, TypeError):
        return None
