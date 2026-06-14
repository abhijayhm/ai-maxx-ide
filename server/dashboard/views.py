from __future__ import annotations

from django.conf import settings
from django.http import HttpRequest, HttpResponse, JsonResponse
from django.shortcuts import render
from django.views.decorators.csrf import csrf_protect
from django.views.decorators.http import require_GET, require_POST
from rest_framework import status
from rest_framework.decorators import api_view, authentication_classes, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response

from standalone.bootstrap import app_root, is_frozen, repo_root
from standalone.script_runner import get_job, list_scripts, start_script


def _is_local(request: HttpRequest) -> bool:
    addr = request.META.get("REMOTE_ADDR", "")
    return addr in {"127.0.0.1", "::1"}


@require_GET
def dashboard_page(request: HttpRequest) -> HttpResponse:
    if not _is_local(request):
        return HttpResponse("Dashboard is only available on localhost.", status=403)

    context = {
        "scripts": list_scripts(),
        "repo_root": str(repo_root()),
        "app_root": str(app_root()),
        "frozen": is_frozen(),
        "bind_host": settings.BIND_HOST,
        "bind_port": settings.BIND_PORT,
    }
    return render(request, "dashboard/index.html", context)


@csrf_protect
@require_POST
def dashboard_run_form(request: HttpRequest) -> HttpResponse:
    if not _is_local(request):
        return HttpResponse("Forbidden", status=403)

    script_id = request.POST.get("script_id", "")
    try:
        job = start_script(script_id)
    except (ValueError, FileNotFoundError) as exc:
        return render(
            request,
            "dashboard/index.html",
            {
                "scripts": list_scripts(),
                "repo_root": str(repo_root()),
                "app_root": str(app_root()),
                "frozen": is_frozen(),
                "bind_host": settings.BIND_HOST,
                "bind_port": settings.BIND_PORT,
                "error": str(exc),
            },
            status=400,
        )

    return render(
        request,
        "dashboard/index.html",
        {
            "scripts": list_scripts(),
            "repo_root": str(repo_root()),
            "app_root": str(app_root()),
            "frozen": is_frozen(),
            "bind_host": settings.BIND_HOST,
            "bind_port": settings.BIND_PORT,
            "last_job": job.to_dict(),
        },
    )


@api_view(["GET"])
@authentication_classes([])
@permission_classes([AllowAny])
def dashboard_scripts_view(request):
    if not _is_local(request):
        return Response({"detail": "Forbidden"}, status=status.HTTP_403_FORBIDDEN)
    return Response({"scripts": list_scripts(), "repo_root": str(repo_root())})


@api_view(["POST"])
@authentication_classes([])
@permission_classes([AllowAny])
def dashboard_run_view(request):
    if not _is_local(request):
        return Response({"detail": "Forbidden"}, status=status.HTTP_403_FORBIDDEN)

    script_id = request.data.get("script_id") or request.data.get("script")
    if not script_id:
        return Response({"detail": "script_id is required"}, status=status.HTTP_400_BAD_REQUEST)

    try:
        job = start_script(str(script_id))
    except ValueError as exc:
        return Response({"detail": str(exc)}, status=status.HTTP_400_BAD_REQUEST)
    except FileNotFoundError as exc:
        return Response({"detail": str(exc)}, status=status.HTTP_404_NOT_FOUND)

    return Response(job.to_dict(), status=status.HTTP_202_ACCEPTED)


@api_view(["GET"])
@authentication_classes([])
@permission_classes([AllowAny])
def dashboard_job_view(request, script_id: str):
    if not _is_local(request):
        return Response({"detail": "Forbidden"}, status=status.HTTP_403_FORBIDDEN)

    job = get_job(script_id)
    if job is None:
        return Response({"detail": "No job for this script yet"}, status=status.HTTP_404_NOT_FOUND)
    return Response(job.to_dict())
