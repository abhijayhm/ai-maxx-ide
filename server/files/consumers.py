"""WebSocket workspace sync — metadata + streamed inline file batches."""

import asyncio
import json

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from django.conf import settings
from pathlib import Path

from core.models import Workspace
from files.sync_service import (
    build_workspace_sync_tree,
    collect_inline_paths,
    fetch_sync_file_batch,
)


@database_sync_to_async
def _get_workspace(workspace_id: int, device_id: int):
    try:
        return Workspace.objects.get(id=workspace_id, device_id=device_id, is_active=True)
    except Workspace.DoesNotExist:
        return None


@database_sync_to_async
def _bind_cursor(workspace):
    from agents.cursor_bridge import bind_cursor_agent

    if not settings.CURSOR_API_KEY:
        return None, "cursor_unavailable"
    try:
        agent_id = bind_cursor_agent(workspace)
    except Exception as exc:
        return None, str(exc)
    if not agent_id:
        return None, "cursor_bind_failed"
    return agent_id, None


class WorkspaceSyncConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        self.workspace_id = int(self.scope["url_route"]["kwargs"]["workspace_id"])
        self.device = self.scope.get("device")
        self.cancelled = False
        self._sync_task: asyncio.Task | None = None

        if not self.scope.get("ws_authenticated") or self.device is None:
            await self.close(code=4401)
            return

        scope_workspace = self.scope.get("workspace")
        if scope_workspace is not None and scope_workspace.id != self.workspace_id:
            await self.close(code=4403)
            return

        self.workspace = await _get_workspace(self.workspace_id, self.device.id)
        if self.workspace is None:
            await self.close(code=4404)
            return

        await self.accept()
        await self.send_json({"type": "ready", "workspace_id": self.workspace_id})

    async def disconnect(self, code):
        self.cancelled = True
        if self._sync_task is not None:
            self._sync_task.cancel()

    async def receive(self, text_data=None, bytes_data=None):
        if text_data is None:
            return
        try:
            content = json.loads(text_data)
        except json.JSONDecodeError:
            await self.send_json(
                {"type": "error", "code": "invalid_json", "message": "Invalid JSON"}
            )
            return

        msg_type = content.get("type")
        if msg_type == "start":
            if self._sync_task is not None and not self._sync_task.done():
                await self.send_json(
                    {
                        "type": "error",
                        "code": "sync_in_progress",
                        "message": "Sync already running.",
                    }
                )
                return
            self.cancelled = False
            self._sync_task = asyncio.create_task(self._run_sync())
        elif msg_type == "cancel":
            self.cancelled = True

    async def _run_sync(self):
        try:
            await self.send_json({"type": "sync_started", "workspace_id": self.workspace_id})

            asyncio.create_task(self._emit_bind_cursor())

            try:
                tree = await database_sync_to_async(build_workspace_sync_tree)(self.workspace)
            except FileNotFoundError:
                await self.send_json(
                    {
                        "type": "error",
                        "code": "not_found",
                        "message": "Workspace path not found.",
                    }
                )
                return

            if self.cancelled:
                return

            inline_paths = collect_inline_paths(tree)
            summary = tree.get("sync_summary", {})
            await self.send_json(
                {
                    "type": "metadata",
                    "tree": tree,
                    "files_total": len(inline_paths),
                    "sync_summary": summary,
                }
            )

            workspace_root = Path(self.workspace.absolute_path)
            batch_size = settings.SYNC_FILES_BATCH_MAX_PATHS
            files_done = 0

            for offset in range(0, len(inline_paths), batch_size):
                if self.cancelled:
                    return

                batch_paths = inline_paths[offset : offset + batch_size]
                files, skipped = await database_sync_to_async(fetch_sync_file_batch)(
                    workspace_root, batch_paths
                )
                files_done += len(files)

                await self.send_json(
                    {
                        "type": "files",
                        "files": files,
                        "skipped": skipped,
                        "files_done": files_done,
                        "files_total": len(inline_paths),
                    }
                )

            if self.cancelled:
                return

            await self.send_json(
                {
                    "type": "complete",
                    "workspace_id": self.workspace_id,
                    "sync_summary": summary,
                }
            )
        except asyncio.CancelledError:
            return
        except Exception as exc:
            await self.send_json(
                {
                    "type": "error",
                    "code": "sync_failed",
                    "message": str(exc),
                }
            )

    async def _emit_bind_cursor(self):
        # Heavy Cursor bridge creation blocks Daphne during sync; bind lazily on
        # first agent message when a real API key is configured.
        if settings.CURSOR_API_KEY:
            if self.cancelled:
                return
            await self.send_json(
                {
                    "type": "bind_cursor",
                    "status": "deferred",
                    "message": "Cursor agent binds on first message",
                }
            )
            return

        bind_timeout = getattr(settings, "CURSOR_BIND_TIMEOUT_SECONDS", 15.0)
        try:
            agent_id, error = await asyncio.wait_for(
                _bind_cursor(self.workspace),
                timeout=bind_timeout,
            )
        except asyncio.TimeoutError:
            if self.cancelled:
                return
            await self.send_json(
                {
                    "type": "bind_cursor",
                    "status": "error",
                    "message": "cursor_bind_timeout",
                }
            )
            return
        if self.cancelled:
            return
        if error:
            await self.send_json(
                {
                    "type": "bind_cursor",
                    "status": "error",
                    "message": error,
                }
            )
        else:
            await self.send_json(
                {
                    "type": "bind_cursor",
                    "status": "ok",
                    "agent_id": agent_id,
                }
            )

    async def send_json(self, content):
        await self.send(text_data=json.dumps(content))
