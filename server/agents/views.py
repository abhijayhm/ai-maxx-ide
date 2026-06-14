import asyncio

from rest_framework import status
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.response import Response

from agents.cursor_bridge import ensure_session_agent, get_status, list_models, stop_run
from core.authentication import DeviceAPIKeyAuthentication
from core.models import AgentMessage, AgentSession
from core.permissions import IsRegisteredDevice, RequiresWorkspace, get_workspace_from_request
from core.serializers import AgentMessageSerializer, AgentSessionSerializer


def _run_async(coro):
    try:
        loop = asyncio.get_event_loop()
        if loop.is_running():
            asyncio.ensure_future(coro)
            return
    except RuntimeError:
        pass
    asyncio.run(coro)


@api_view(["GET", "POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def agent_sessions_view(request):
    workspace = get_workspace_from_request(request)
    device = request.user

    if request.method == "GET":
        sessions = AgentSession.objects.filter(
            workspace=workspace, device=device
        ).order_by("-created_at")
        return Response(AgentSessionSerializer(sessions, many=True).data)

    session = AgentSession.objects.create(workspace=workspace, device=device)
    model = request.data.get("model")
    _run_async(ensure_session_agent(workspace, session, model))
    return Response(AgentSessionSerializer(session).data, status=status.HTTP_201_CREATED)


@api_view(["GET"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def agent_models_view(request):
    workspace = get_workspace_from_request(request)
    models = asyncio.run(list_models(workspace))
    return Response(models)


@api_view(["GET"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def agent_messages_view(request):
    workspace = get_workspace_from_request(request)
    qs = AgentMessage.objects.filter(workspace=workspace, device=request.user).order_by(
        "-timestamp"
    )
    limit = int(request.query_params.get("limit", 50))
    offset = int(request.query_params.get("offset", 0))
    messages = qs[offset : offset + limit]
    return Response(AgentMessageSerializer(messages, many=True).data)


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def agent_stop_view(request):
    session_id = request.data.get("session_id")
    if session_id is None:
        return Response({"stopped": False, "error": "session_id required"}, status=400)
    status_info = get_status(int(session_id))
    if not status_info["running"]:
        return Response({"stopped": False})
    _run_async(stop_run(int(session_id)))
    return Response({"stopped": True})


@api_view(["GET"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def agent_status_view(request):
    session_id = request.query_params.get("session_id")
    if session_id is None:
        return Response({"running": False, "run_id": ""})
    return Response(get_status(int(session_id)))
