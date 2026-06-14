"""Filesystem watchdog for exposed directories."""

from __future__ import annotations

import asyncio
import logging
import os
import threading
from pathlib import Path

from watchdog.events import FileSystemEvent, FileSystemEventHandler
from watchdog.observers import Observer

from core.utils.paths import get_exposed_roots
from ide.route_tree import _asset_name

logger = logging.getLogger(__name__)


def _path_type(path: str, is_directory: bool) -> str:
    if is_directory:
        return "folder"
    return "file"


class _ExposedHandler(FileSystemEventHandler):
    def __init__(self, service: "ExposedWatchdog"):
        self._service = service

    def on_created(self, event: FileSystemEvent) -> None:
        self._service._emit("created", event)

    def on_deleted(self, event: FileSystemEvent) -> None:
        self._service._emit("deleted", event)

    def on_modified(self, event: FileSystemEvent) -> None:
        # User spec: ignore file updates.
        pass

    def on_moved(self, event: FileSystemEvent) -> None:
        src = getattr(event, "src_path", None)
        dest = getattr(event, "dest_path", None)
        if src:
            self._service._emit_raw("deleted", src, event.is_directory)
        if dest:
            self._service._emit_raw("created", dest, event.is_directory)


class ExposedWatchdog:
    """Singleton observer; fan-out to asyncio queues registered by WS consumers."""

    def __init__(self) -> None:
        self._observer: Observer | None = None
        self._lock = threading.Lock()
        self._subscribers: set[asyncio.Queue] = set()

    def ensure_started(self) -> None:
        with self._lock:
            if self._observer is not None:
                return
            observer = Observer()
            handler = _ExposedHandler(self)
            for root in get_exposed_roots():
                if root.is_dir():
                    observer.schedule(handler, str(root), recursive=True)
            observer.start()
            self._observer = observer
            logger.info("ExposedWatchdog started for %s roots", len(get_exposed_roots()))

    def subscribe(self) -> asyncio.Queue:
        self.ensure_started()
        queue: asyncio.Queue = asyncio.Queue()
        self._subscribers.add(queue)
        return queue

    def unsubscribe(self, queue: asyncio.Queue) -> None:
        self._subscribers.discard(queue)

    def _emit(self, event_type: str, event: FileSystemEvent) -> None:
        self._emit_raw(event_type, event.src_path, event.is_directory)

    def _emit_raw(self, event_type: str, path: str, is_directory: bool) -> None:
        node = {
            "path": path,
            "asset": _asset_name(Path(path)),
            "path_type": _path_type(path, is_directory),
        }
        payload = {"type": "watchdog", "event": event_type, "node": node}
        for queue in list(self._subscribers):
            try:
                queue.put_nowait(payload)
            except asyncio.QueueFull:
                pass


exposed_watchdog = ExposedWatchdog()
