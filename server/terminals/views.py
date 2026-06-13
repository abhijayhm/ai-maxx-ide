import subprocess
import time

from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.response import Response

from core.authentication import DeviceAPIKeyAuthentication
from core.exceptions import error_response
from core.permissions import IsRegisteredDevice, RequiresWorkspace, get_workspace_from_request
from core.utils.paths import PathNotAllowedError, resolve_allowed_path
from terminals.models import Terminal, TerminalStatus
from terminals.pty_manager import PtyManager
from terminals.services import close_stale_terminals


def _serialize_terminal(t: Terminal) -> dict:
    return {
        "id": t.id,
        "name": t.name,
        "shell": t.shell,
        "cwd": t.cwd,
        "status": t.status,
        "pid": t.pid,
        "cols": t.cols,
        "rows": t.rows,
        "last_used": t.last_used.isoformat(),
        "created_at": t.created_at.isoformat(),
    }


@api_view(["GET", "POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def terminal_list_create_view(request):
    device = request.user
    workspace = get_workspace_from_request(request)
    close_stale_terminals(device=device, workspace_id=workspace.id)

    if request.method == "GET":
        include_closed = request.query_params.get("include_closed") == "1"
        qs = Terminal.objects.filter(device=device, workspace=workspace)
        if not include_closed:
            qs = qs.filter(status=TerminalStatus.ACTIVE)
        return Response([_serialize_terminal(t) for t in qs.order_by("-created_at")])

    shell = request.data.get("shell", "powershell")
    cwd = request.data.get("cwd", workspace.absolute_path)
    cols = int(request.data.get("cols", 80))
    rows = int(request.data.get("rows", 24))

    try:
        cwd_path = resolve_allowed_path(cwd)
    except PathNotAllowedError as exc:
        return error_response("path_not_allowed", exc.detail, status.HTTP_403_FORBIDDEN)

    active_count = Terminal.objects.filter(
        device=device, workspace=workspace, status=TerminalStatus.ACTIVE
    ).count()
    name = request.data.get("name") or shell or f"Terminal {active_count + 1}"

    terminal = Terminal.objects.create(
        device=device,
        workspace=workspace,
        name=name,
        shell=shell,
        cwd=str(cwd_path),
        cols=cols,
        rows=rows,
        status=TerminalStatus.ACTIVE,
    )
    return Response(_serialize_terminal(terminal), status=status.HTTP_201_CREATED)


@api_view(["GET", "PATCH", "DELETE"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def terminal_detail_view(request, terminal_id):
    device = request.user
    workspace = get_workspace_from_request(request)
    close_stale_terminals(device=device, workspace_id=workspace.id)

    include_closed = request.query_params.get("include_closed") == "1"

    try:
        terminal = Terminal.objects.get(id=terminal_id, device=device, workspace=workspace)
    except Terminal.DoesNotExist:
        return error_response("not_found", "Terminal not found.", status.HTTP_404_NOT_FOUND)

    if terminal.status == TerminalStatus.CLOSED and not include_closed:
        return error_response("terminal_closed", "Terminal is closed.", status.HTTP_404_NOT_FOUND)

    if request.method == "GET":
        return Response(_serialize_terminal(terminal))

    if request.method == "PATCH":
        if terminal.status == TerminalStatus.CLOSED:
            return error_response("terminal_closed", "Terminal is closed.", status.HTTP_409_CONFLICT)
        if "name" in request.data:
            terminal.name = request.data["name"]
        if "cols" in request.data:
            terminal.cols = int(request.data["cols"])
        if "rows" in request.data:
            terminal.rows = int(request.data["rows"])
        terminal.last_used = timezone.now()
        terminal.save()
        return Response(_serialize_terminal(terminal))

    if terminal.status == TerminalStatus.ACTIVE:
        PtyManager.kill(terminal.pid)
    terminal.pid = None
    terminal.status = TerminalStatus.CLOSED
    terminal.save(update_fields=["pid", "status"])
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def terminal_exec_view(request, terminal_id):
    device = request.user
    workspace = get_workspace_from_request(request)
    close_stale_terminals(device=device, workspace_id=workspace.id)

    try:
        terminal = Terminal.objects.get(id=terminal_id, device=device, workspace=workspace)
    except Terminal.DoesNotExist:
        return error_response("not_found", "Terminal not found.", status.HTTP_404_NOT_FOUND)

    if terminal.status == TerminalStatus.CLOSED:
        return error_response("terminal_closed", "Terminal is closed.", status.HTTP_409_CONFLICT)

    command = request.data.get("command", "")
    timeout_ms = int(request.data.get("timeout_ms", 30000))
    cwd_raw = request.data.get("cwd", terminal.cwd)

    try:
        cwd = str(resolve_allowed_path(cwd_raw))
    except PathNotAllowedError as exc:
        return error_response("path_not_allowed", exc.detail, status.HTTP_403_FORBIDDEN)

    if terminal.shell == "powershell":
        cmd = ["powershell", "-NoProfile", "-Command", command]
    else:
        cmd = ["cmd", "/c", command]

    start = time.monotonic()
    try:
        proc = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout_ms / 1000,
            check=False,
        )
        duration_ms = int((time.monotonic() - start) * 1000)
        terminal.last_used = timezone.now()
        terminal.save(update_fields=["last_used"])
        return Response(
            {
                "exit_code": proc.returncode,
                "stdout": proc.stdout,
                "stderr": proc.stderr,
                "duration_ms": duration_ms,
            }
        )
    except subprocess.TimeoutExpired as exc:
        duration_ms = int((time.monotonic() - start) * 1000)
        return Response(
            {
                "exit_code": -1,
                "stdout": exc.stdout or "",
                "stderr": exc.stderr or "Timeout",
                "duration_ms": duration_ms,
            },
            status=status.HTTP_408_REQUEST_TIMEOUT,
        )
