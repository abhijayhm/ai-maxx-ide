"""REST endpoints for route trees and workspace open."""

from pathlib import Path

from rest_framework import status
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.response import Response

from core.authentication import DeviceAPIKeyAuthentication
from core.exceptions import error_response
from core.models import Workspace
from core.permissions import IsRegisteredDevice, RequiresWorkspace, get_workspace_from_request
from core.utils.paths import PathNotAllowedError, resolve_allowed_path

from ide.route_tree import build_exposed_routes_tree, build_workspace_tree


@api_view(["GET"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice])
def exposed_routes_tree_view(request):
    return Response(build_exposed_routes_tree())


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice])
def workspace_open_view(request):
    """Get or create workspace from an absolute folder path."""
    raw_path = request.data.get("path") or request.data.get("absolute_path") or ""
    if not str(raw_path).strip():
        return error_response("invalid_request", "path is required.", status.HTTP_400_BAD_REQUEST)

    try:
        abs_path = resolve_allowed_path(str(raw_path))
    except PathNotAllowedError as exc:
        return error_response("path_not_allowed", exc.detail, status.HTTP_403_FORBIDDEN)

    if not abs_path.is_dir():
        return error_response(
            "not_a_directory",
            "Workspace path must be an existing folder.",
            status.HTTP_400_BAD_REQUEST,
        )

    device = request.user
    label = abs_path.name or str(abs_path)
    workspace, created = Workspace.objects.update_or_create(
        device=device,
        absolute_path=str(abs_path),
        defaults={"label": label, "is_active": True},
    )

    return Response(
        {
            "id": workspace.id,
            "path": workspace.absolute_path,
            "label": workspace.label,
            "created": created,
        },
        status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
    )


@api_view(["GET"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def workspace_tree_view(request, workspace_id):
    workspace = get_workspace_from_request(request)
    if workspace.id != workspace_id:
        return error_response("workspace_mismatch", "Workspace mismatch.", status.HTTP_403_FORBIDDEN)

    root = Path(workspace.absolute_path)
    try:
        tree = build_workspace_tree(root)
    except NotADirectoryError:
        return error_response(
            "not_a_directory",
            "Workspace path is not a directory.",
            status.HTTP_404_NOT_FOUND,
        )
    return Response(tree)
