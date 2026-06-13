import mimetypes
import subprocess
from pathlib import Path

from django.conf import settings
from django.http import FileResponse, Http404
from rest_framework import status
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.response import Response

from core.authentication import DeviceAPIKeyAuthentication
from core.exceptions import error_response
from core.models import Workspace
from core.permissions import IsRegisteredDevice, RequiresWorkspace, get_workspace_from_request
from core.utils.paths import PathNotAllowedError, resolve_allowed_path
from files.sync_service import build_workspace_sync_tree, fetch_sync_file_batch
from files.tree import (
    list_directory,
    list_roots,
    read_file_entry,
    search_files,
)


@api_view(["GET"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice])
def files_roots_view(request):
    return Response(list_roots())


@api_view(["GET"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice])
def files_by_path_view(request):
    raw_path = request.query_params.get("path", "")
    if not raw_path:
        return Response(list_roots())

    try:
        path = resolve_allowed_path(raw_path)
    except PathNotAllowedError as exc:
        return error_response("path_not_allowed", exc.detail, status.HTTP_403_FORBIDDEN)

    if not path.exists():
        return error_response("not_found", "Path not found.", status.HTTP_404_NOT_FOUND)

    if path.is_dir():
        return Response(list_directory(path))
    return Response(read_file_entry(path))


@api_view(["GET"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice])
def files_download_view(request):
    raw_path = request.query_params.get("path", "")
    try:
        path = resolve_allowed_path(raw_path)
    except PathNotAllowedError as exc:
        return error_response("path_not_allowed", exc.detail, status.HTTP_403_FORBIDDEN)

    if not path.is_file():
        return error_response("not_found", "File not found.", status.HTTP_404_NOT_FOUND)

    content_type, _ = mimetypes.guess_type(str(path))
    return FileResponse(path.open("rb"), content_type=content_type or "application/octet-stream")


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice])
def files_mkdir_view(request):
    parent_raw = request.data.get("path", "")
    name = request.data.get("name", "")
    if not name:
        return error_response("invalid_request", "Name is required.", status.HTTP_400_BAD_REQUEST)

    try:
        parent = resolve_allowed_path(parent_raw)
    except PathNotAllowedError as exc:
        return error_response("path_not_allowed", exc.detail, status.HTTP_403_FORBIDDEN)

    if not parent.is_dir():
        return error_response("invalid_request", "Parent must be a directory.", status.HTTP_400_BAD_REQUEST)

    new_dir = parent / name
    new_dir.mkdir(parents=False, exist_ok=False)
    return Response({"path": str(new_dir)}, status=status.HTTP_201_CREATED)


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice])
def files_touch_view(request):
    parent_raw = request.data.get("path", "")
    name = request.data.get("name", "")
    if not name:
        return error_response("invalid_request", "Name is required.", status.HTTP_400_BAD_REQUEST)

    try:
        parent = resolve_allowed_path(parent_raw)
    except PathNotAllowedError as exc:
        return error_response("path_not_allowed", exc.detail, status.HTTP_403_FORBIDDEN)

    if not parent.is_dir():
        return error_response("invalid_request", "Parent must be a directory.", status.HTTP_400_BAD_REQUEST)

    new_file = parent / name
    new_file.touch(exist_ok=False)
    return Response({"path": str(new_file)}, status=status.HTTP_201_CREATED)


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice])
def workspace_sync_view(request, workspace_id):
    """Phase 1 sync: metadata-only workspace tree (fast JSON snapshot)."""
    device = request.user
    try:
        workspace = Workspace.objects.get(id=workspace_id, device=device, is_active=True)
    except Workspace.DoesNotExist:
        return error_response(
            "workspace_not_found", "Workspace not found.", status.HTTP_404_NOT_FOUND
        )

    include_content = request.query_params.get("include_content", "").lower() in {
        "1",
        "true",
        "yes",
    }
    try:
        if include_content:
            from files.tree import attach_sync_summary, build_sync_tree

            root = Path(workspace.absolute_path)
            if not root.exists():
                return error_response(
                    "not_found", "Workspace path not found.", status.HTTP_404_NOT_FOUND
                )
            tree = build_sync_tree(root, include_content=True)
            return Response(attach_sync_summary(tree))
        tree = build_workspace_sync_tree(workspace)
    except FileNotFoundError:
        return error_response("not_found", "Workspace path not found.", status.HTTP_404_NOT_FOUND)
    return Response(tree)


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice])
def workspace_sync_files_view(request, workspace_id):
    """Phase 2 sync: fetch inline file bodies for a batch of workspace paths."""
    device = request.user
    try:
        workspace = Workspace.objects.get(id=workspace_id, device=device, is_active=True)
    except Workspace.DoesNotExist:
        return error_response(
            "workspace_not_found", "Workspace not found.", status.HTTP_404_NOT_FOUND
        )

    paths = request.data.get("paths")
    if not isinstance(paths, list) or not paths:
        return error_response(
            "invalid_request",
            "paths must be a non-empty list.",
            status.HTTP_400_BAD_REQUEST,
        )

    max_paths = settings.SYNC_FILES_BATCH_MAX_PATHS
    if len(paths) > max_paths:
        return error_response(
            "invalid_request",
            f"At most {max_paths} paths per request.",
            status.HTTP_400_BAD_REQUEST,
        )

    workspace_root = Path(workspace.absolute_path)
    files, skipped = fetch_sync_file_batch(workspace_root, paths)
    return Response({"files": files, "skipped": skipped})


@api_view(["GET"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def search_files_view(request):
    workspace = get_workspace_from_request(request)
    query = request.query_params.get("q", "")
    limit = int(request.query_params.get("limit", 50))
    if not query:
        return Response([])

    root = Path(workspace.absolute_path)
    return Response(search_files(root, query, limit=limit))


@api_view(["POST"])
@authentication_classes([DeviceAPIKeyAuthentication])
@permission_classes([IsRegisteredDevice, RequiresWorkspace])
def search_grep_view(request):
    workspace = get_workspace_from_request(request)
    pattern = request.data.get("pattern", "")
    glob_pattern = request.data.get("glob", "*")
    case_sensitive = request.data.get("case_sensitive", False)

    if not pattern:
        return error_response("invalid_request", "Pattern is required.", status.HTTP_400_BAD_REQUEST)

    root = Path(workspace.absolute_path)
    results = _run_grep(root, pattern, glob_pattern, case_sensitive)
    return Response(results)


def _run_grep(root: Path, pattern: str, glob_pattern: str, case_sensitive: bool) -> list[dict]:
    cmd = ["rg", "--json", pattern, str(root)]
    if not case_sensitive:
        cmd.insert(1, "-i")
    if glob_pattern and glob_pattern != "*":
        cmd.extend(["--glob", glob_pattern])

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30, check=False)
    except FileNotFoundError:
        return _grep_fallback(root, pattern, case_sensitive)

    if proc.returncode not in (0, 1):
        return _grep_fallback(root, pattern, case_sensitive)

    return _parse_rg_json(proc.stdout, root)


def _grep_fallback(root: Path, pattern: str, case_sensitive: bool) -> list[dict]:
    import re

    flags = 0 if case_sensitive else re.IGNORECASE
    regex = re.compile(pattern, flags)
    results = []
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        matches = []
        for i, line in enumerate(text.splitlines(), start=1):
            if regex.search(line):
                matches.append({"line": i, "text": line})
        if matches:
            rel = path.relative_to(root).as_posix()
            results.append(
                {
                    "path": rel,
                    "line_start": matches[0]["line"],
                    "line_end": matches[-1]["line"],
                    "matches": matches,
                }
            )
    return results


def _parse_rg_json(stdout: str, root: Path) -> list[dict]:
    import json

    grouped: dict[str, list] = {}
    for line in stdout.splitlines():
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("type") != "match":
            continue
        data = obj.get("data", {})
        path_text = data.get("path", {}).get("text", "")
        line_num = data.get("line_number", 0)
        text = data.get("lines", {}).get("text", "").rstrip("\n")
        try:
            rel = Path(path_text).relative_to(root).as_posix()
        except ValueError:
            rel = path_text
        grouped.setdefault(rel, []).append({"line": line_num, "text": text})

    results = []
    for path, matches in grouped.items():
        results.append(
            {
                "path": path,
                "line_start": matches[0]["line"],
                "line_end": matches[-1]["line"],
                "matches": matches,
            }
        )
    return results
