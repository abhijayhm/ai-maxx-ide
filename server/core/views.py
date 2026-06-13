from pathlib import Path

from django.conf import settings
from rest_framework import status
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from core.authentication import DeviceAPIKeyAuthentication
from core.exceptions import error_response
from core.models import DeviceIdentifier, Workspace
from core.permissions import IsRegisteredDevice
from core.serializers import (
    DeviceIdentifierSerializer,
    DeviceRegisterSerializer,
    WorkspaceCreateSerializer,
    WorkspacePatchSerializer,
    WorkspaceSerializer,
)
from core.utils.hashing import compute_device_hash
from core.utils.paths import PathNotAllowedError, resolve_allowed_path


@api_view(["GET"])
@authentication_classes([])
@permission_classes([AllowAny])
def health_view(request):
    return Response({"ok": True})


@api_view(["POST"])
@authentication_classes([])
@permission_classes([AllowAny])
def device_register_view(request):
    serializer = DeviceRegisterSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    data = serializer.validated_data["data"]
    provided_hash = serializer.validated_data["hash"]
    computed = compute_device_hash(data)

    if provided_hash != computed:
        return error_response(
            "hash_mismatch",
            "Provided hash does not match computed hash.",
            status.HTTP_400_BAD_REQUEST,
        )

    device, created = DeviceIdentifier.objects.update_or_create(
        hash=computed,
        defaults={"data": data, "is_active": True},
    )
    device.save(update_fields=["last_seen_at"])

    return Response(
        {"id": device.id, "hash": device.hash, "registered": True},
        status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
    )


@api_view(["POST"])
@authentication_classes([])
@permission_classes([AllowAny])
def device_identifier_view(request):
    api_key = request.headers.get("X-API-Key", "")
    if api_key != settings.API_KEY:
        return error_response("invalid_api_key", "Invalid API key.", status.HTTP_403_FORBIDDEN)

    serializer = DeviceIdentifierSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    computed = compute_device_hash(serializer.validated_data["data"])
    return Response({"hash": computed})


@api_view(["GET", "POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice])
def workspace_list_create_view(request):
    device = request.user

    if request.method == "GET":
        workspaces = Workspace.objects.filter(device=device, is_active=True)
        return Response(WorkspaceSerializer(workspaces, many=True).data)

    serializer = WorkspaceCreateSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    try:
        abs_path = resolve_allowed_path(serializer.validated_data["absolute_path"])
    except PathNotAllowedError as exc:
        return error_response("path_not_allowed", exc.detail, status.HTTP_403_FORBIDDEN)

    label = abs_path.name or str(abs_path)
    workspace, _created = Workspace.objects.update_or_create(
        device=device,
        absolute_path=str(abs_path),
        defaults={"label": label, "is_active": True},
    )

    from agents.cursor_bridge import bind_cursor_agent

    try:
        agent_id = bind_cursor_agent(workspace)
        if agent_id:
            workspace.cursor_agent_id = agent_id
            workspace.save(update_fields=["cursor_agent_id", "updated_at"])
    except Exception:
        pass

    return Response(
        WorkspaceSerializer(workspace).data,
        status=status.HTTP_201_CREATED,
    )


@api_view(["GET", "PATCH", "DELETE"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice])
def workspace_detail_view(request, workspace_id):
    device = request.user

    try:
        workspace = Workspace.objects.get(id=workspace_id, device=device)
    except Workspace.DoesNotExist:
        return error_response(
            "workspace_not_found", "Workspace not found.", status.HTTP_404_NOT_FOUND
        )

    if request.method == "GET":
        return Response(WorkspaceSerializer(workspace).data)

    if request.method == "PATCH":
        serializer = WorkspacePatchSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        for field, value in serializer.validated_data.items():
            setattr(workspace, field, value)
        workspace.save()
        return Response(WorkspaceSerializer(workspace).data)

    workspace.is_active = False
    workspace.save(update_fields=["is_active", "updated_at"])
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice])
def workspace_bind_cursor_view(request, workspace_id):
    device = request.user

    if not settings.CURSOR_API_KEY:
        return error_response(
            "cursor_unavailable",
            "Cursor API key not configured.",
            status.HTTP_503_SERVICE_UNAVAILABLE,
        )

    try:
        workspace = Workspace.objects.get(
            id=workspace_id, device=device, is_active=True
        )
    except Workspace.DoesNotExist:
        return error_response(
            "workspace_not_found", "Workspace not found.", status.HTTP_404_NOT_FOUND
        )

    from agents.cursor_bridge import bind_cursor_agent

    try:
        agent_id = bind_cursor_agent(workspace)
    except Exception as exc:
        return error_response(
            "cursor_unavailable",
            str(exc),
            status.HTTP_503_SERVICE_UNAVAILABLE,
        )

    if not agent_id:
        return error_response(
            "cursor_unavailable",
            "Failed to bind Cursor agent.",
            status.HTTP_503_SERVICE_UNAVAILABLE,
        )

    workspace.cursor_agent_id = agent_id
    workspace.save(update_fields=["cursor_agent_id", "updated_at"])
    return Response({"cursor_agent_id": agent_id})
