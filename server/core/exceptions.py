"""Shared API error helpers."""

from rest_framework import status
from rest_framework.exceptions import APIException
from rest_framework.response import Response
from rest_framework.views import exception_handler


class CodedAPIException(APIException):
    """API exception with a machine-readable code."""

    default_code = "error"

    def __init__(self, detail=None, code=None, status_code=None):
        if status_code is not None:
            self.status_code = status_code
        if code is not None:
            self.default_code = code
        super().__init__(detail=detail, code=code)


def error_response(code: str, detail: str, status_code: int = status.HTTP_400_BAD_REQUEST):
    return Response({"code": code, "detail": detail}, status=status_code)


def api_exception_handler(exc, context):
    response = exception_handler(exc, context)
    if response is not None:
        code = getattr(exc, "default_code", "error")
        if hasattr(exc, "detail"):
            detail = exc.detail
            if isinstance(detail, list):
                detail = detail[0] if detail else str(exc)
            elif isinstance(detail, dict):
                detail = next(iter(detail.values()), str(exc))
                if isinstance(detail, list):
                    detail = detail[0]
        else:
            detail = str(exc)
        response.data = {"code": code, "detail": str(detail)}
    return response
