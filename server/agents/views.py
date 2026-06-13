from rest_framework import status
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.response import Response

from agents.cursor_bridge import get_status, stop_run
from core.authentication import DeviceAPIKeyAuthentication
from core.exceptions import error_response
from core.models import AgentMessage
from core.permissions import IsRegisteredDevice, RequiresWorkspace, get_workspace_from_request
from core.serializers import AgentMessageSerializer


@api_view(["GET"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def agent_messages_view(request):
    workspace = get_workspace_from_request(request)
    qs = AgentMessage.objects.filter(workspace=workspace, device=request.user).order_by("-timestamp")
    limit = int(request.query_params.get("limit", 50))
    offset = int(request.query_params.get("offset", 0))
    messages = qs[offset : offset + limit]
    return Response(AgentMessageSerializer(messages, many=True).data)


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def agent_stop_view(request):
    workspace = get_workspace_from_request(request)
    status_info = get_status(workspace.id)
    if not status_info["running"]:
        return Response({"stopped": False})
    awaitable = stop_run(workspace.id)
    import asyncio

    try:
        loop = asyncio.get_event_loop()
        if loop.is_running():
            asyncio.ensure_future(awaitable)
        else:
            loop.run_until_complete(awaitable)
    except RuntimeError:
        asyncio.run(awaitable)
    return Response({"stopped": True})


@api_view(["GET"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def agent_status_view(request):
    workspace = get_workspace_from_request(request)
    return Response(get_status(workspace.id))
