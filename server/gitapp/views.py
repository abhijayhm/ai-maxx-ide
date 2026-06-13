from rest_framework import status
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.response import Response

from core.authentication import DeviceAPIKeyAuthentication
from core.exceptions import error_response
from core.permissions import IsRegisteredDevice, RequiresWorkspace, get_workspace_from_request
from gitapp.runner import get_git_runner


def _workspace_cwd(request):
    workspace = get_workspace_from_request(request)
    if workspace is None:
        return None, error_response(
            "workspace_not_found", "Workspace not found.", status.HTTP_404_NOT_FOUND
        )
    return workspace, None


@api_view(["GET"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def git_status_view(request):
    workspace, err = _workspace_cwd(request)
    if err:
        return err
    runner = get_git_runner(workspace.absolute_path)
    return Response({"files": runner.status_porcelain()})


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def git_stage_view(request):
    workspace, err = _workspace_cwd(request)
    if err:
        return err
    paths = request.data.get("paths", [])
    proc = get_git_runner(workspace.absolute_path).add(paths)
    return Response({"ok": proc.returncode == 0, "stderr": proc.stderr})


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def git_unstage_view(request):
    workspace, err = _workspace_cwd(request)
    if err:
        return err
    paths = request.data.get("paths", [])
    proc = get_git_runner(workspace.absolute_path).unstage(paths)
    return Response({"ok": proc.returncode == 0, "stderr": proc.stderr})


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def git_discard_view(request):
    workspace, err = _workspace_cwd(request)
    if err:
        return err
    paths = request.data.get("paths", [])
    proc = get_git_runner(workspace.absolute_path).discard(paths)
    return Response({"ok": proc.returncode == 0, "stderr": proc.stderr})


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def git_stash_view(request):
    workspace, err = _workspace_cwd(request)
    if err:
        return err
    message = request.data.get("message", "WIP")
    proc = get_git_runner(workspace.absolute_path).stash(message)
    return Response({"ok": proc.returncode == 0, "stderr": proc.stderr})


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def git_commit_view(request):
    workspace, err = _workspace_cwd(request)
    if err:
        return err
    message = request.data.get("message", "")
    if not message:
        return error_response("invalid_request", "Message is required.", status.HTTP_400_BAD_REQUEST)
    proc = get_git_runner(workspace.absolute_path).commit(message)
    return Response({"ok": proc.returncode == 0, "stderr": proc.stderr, "stdout": proc.stdout})


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def git_sync_view(request):
    workspace, err = _workspace_cwd(request)
    if err:
        return err
    proc = get_git_runner(workspace.absolute_path).sync()
    return Response({"ok": proc.returncode == 0, "stderr": proc.stderr, "stdout": proc.stdout})


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def git_exec_view(request):
    workspace, err = _workspace_cwd(request)
    if err:
        return err
    command = request.data.get("command", [])
    if isinstance(command, str):
        command = command.split()
    try:
        proc = get_git_runner(workspace.absolute_path).exec_allowed(command)
    except ValueError as exc:
        return error_response("invalid_request", str(exc), status.HTTP_400_BAD_REQUEST)
    return Response(
        {
            "exit_code": proc.returncode,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
        }
    )


@api_view(["GET"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def git_branches_view(request):
    workspace, err = _workspace_cwd(request)
    if err:
        return err
    return Response(get_git_runner(workspace.absolute_path).branches())


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def git_checkout_view(request):
    workspace, err = _workspace_cwd(request)
    if err:
        return err
    branch = request.data.get("branch", "")
    if not branch:
        return error_response("invalid_request", "Branch is required.", status.HTTP_400_BAD_REQUEST)
    proc = get_git_runner(workspace.absolute_path).checkout(branch)
    return Response({"ok": proc.returncode == 0, "stderr": proc.stderr})


@api_view(["GET"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def git_log_view(request):
    workspace, err = _workspace_cwd(request)
    if err:
        return err
    limit = int(request.query_params.get("limit", 20))
    commits = get_git_runner(workspace.absolute_path).log(limit=limit)
    return Response({"commits": commits})
