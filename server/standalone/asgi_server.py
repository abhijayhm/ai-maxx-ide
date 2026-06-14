"""Run the ASGI app with Daphne (same stack as ``manage.py runserver``)."""

from __future__ import annotations

import logging

from django.conf import settings

logger = logging.getLogger(__name__)


def run_daphne(host: str, port: int) -> None:
    """Start HTTP + WebSocket server via Twisted/asyncio (required for aiortc remote)."""
    from config.asgi import application
    from daphne.server import Server

    endpoint = f"tcp:port={port}:interface={host}"
    max_ws = int(getattr(settings, "WS_MAX_MESSAGE_BYTES", 4 * 1024 * 1024))
    logger.info("Starting ai-maxx-ide (daphne) on http://%s:%s", host, port)
    Server(
        application=application,
        endpoints=[endpoint],
        signal_handlers=True,
        websocket_max_message_size=max_ws,
        websocket_max_frame_size=max_ws,
        verbosity=1,
    ).run()
