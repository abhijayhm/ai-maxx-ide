"""WebSocket consumers: watchdog, ide_search, git."""

from __future__ import annotations

import asyncio
import json
import threading
from pathlib import Path

from channels.generic.websocket import AsyncWebsocketConsumer
from django.conf import settings

from core.models import Workspace
from gitapp.runner import get_git_runner
from ide.search_service import stream_ide_search
from ide.watchdog_service import exposed_watchdog


class WatchdogConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        if not self.scope.get("ws_authenticated") or self.scope.get("device") is None:
            await self.close(code=4401)
            return
        await self.accept()
        self._queue = exposed_watchdog.subscribe()
        self._pump_task = asyncio.create_task(self._pump())

    async def disconnect(self, close_code):
        if hasattr(self, "_pump_task"):
            self._pump_task.cancel()
        if hasattr(self, "_queue"):
            exposed_watchdog.unsubscribe(self._queue)

    async def _pump(self):
        try:
            while True:
                message = await self._queue.get()
                await self.send(text_data=json.dumps(message))
        except asyncio.CancelledError:
            return

    async def receive(self, text_data=None, bytes_data=None):
        # Keep-alive pings only; filesystem events are pushed.
        if text_data and text_data.strip() == "ping":
            await self.send(text_data=json.dumps({"type": "pong"}))


class IdeSearchConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        if not self.scope.get("ws_authenticated") or self.scope.get("device") is None:
            await self.close(code=4401)
            return
        self.device = self.scope["device"]
        self._search_task: asyncio.Task | None = None
        await self.accept()

    async def disconnect(self, close_code):
        if self._search_task is not None:
            self._search_task.cancel()

    async def receive(self, text_data=None, bytes_data=None):
        if text_data is None:
            return
        try:
            content = json.loads(text_data)
        except json.JSONDecodeError:
            await self.send_json({"type": "error", "code": "invalid_json", "message": "Invalid JSON"})
            return

        msg_type = content.get("type")
        if msg_type == "cancel":
            if self._search_task is not None:
                self._search_task.cancel()
            await self.send_json({"type": "cancelled"})
            return

        if msg_type != "search":
            await self.send_json({"type": "error", "code": "invalid_type", "message": "Expected type search"})
            return

        workspace_id = content.get("workspace_id")
        if workspace_id is None:
            await self.send_json({"type": "error", "code": "workspace_required", "message": "workspace_id required"})
            return

        workspace = await self._get_workspace(workspace_id)
        if workspace is None:
            await self.send_json({"type": "error", "code": "workspace_not_found", "message": "Workspace not found"})
            return

        if self._search_task is not None and not self._search_task.done():
            self._search_task.cancel()

        self._search_task = asyncio.create_task(self._run_search(workspace, content))

    async def _run_search(self, workspace, content: dict):
        await self.send_json({"type": "search_started", "workspace_id": workspace.id})
        root = Path(workspace.absolute_path)
        keyword = content.get("keyword") or content.get("pattern") or ""
        loop = asyncio.get_running_loop()
        queue: asyncio.Queue = asyncio.Queue()

        def worker():
            try:
                for result in stream_ide_search(
                    root,
                    keyword=keyword,
                    match_case=bool(content.get("match_case", False)),
                    match_exact=bool(content.get("match_exact", False)),
                    files_to_include=content.get("files_to_include"),
                    files_to_exclude=content.get("files_to_exclude"),
                ):
                    loop.call_soon_threadsafe(queue.put_nowait, result)
            except Exception as exc:
                loop.call_soon_threadsafe(queue.put_nowait, exc)
            finally:
                loop.call_soon_threadsafe(queue.put_nowait, None)

        threading.Thread(target=worker, daemon=True).start()

        try:
            while True:
                item = await queue.get()
                if item is None:
                    break
                if isinstance(item, Exception):
                    raise item
                await self.send_json({"type": "result", **item})
            await self.send_json({"type": "search_complete"})
        except asyncio.CancelledError:
            await self.send_json({"type": "cancelled"})
        except Exception as exc:
            await self.send_json({"type": "error", "code": "search_failed", "message": str(exc)})

    async def _get_workspace(self, workspace_id):
        from channels.db import database_sync_to_async

        @database_sync_to_async
        def _fetch():
            try:
                return Workspace.objects.get(
                    id=int(workspace_id),
                    device_id=self.device.id,
                    is_active=True,
                )
            except (Workspace.DoesNotExist, TypeError, ValueError):
                return None

        return await _fetch()

    async def send_json(self, content):
        await self.send(text_data=json.dumps(content))


class GitConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        if not self.scope.get("ws_authenticated") or self.scope.get("device") is None:
            await self.close(code=4401)
            return
        self.device = self.scope["device"]
        await self.accept()

    async def receive(self, text_data=None, bytes_data=None):
        if text_data is None:
            return
        try:
            content = json.loads(text_data)
        except json.JSONDecodeError:
            await self.send_json({"type": "error", "code": "invalid_json", "message": "Invalid JSON"})
            return

        msg_type = content.get("type")
        workspace = await self._resolve_workspace(content)
        if workspace is None:
            await self.send_json({"type": "error", "code": "workspace_required", "message": "Valid workspace_id required"})
            return

        runner = await asyncio.to_thread(get_git_runner, workspace.absolute_path)

        try:
            if msg_type == "status":
                files = await asyncio.to_thread(runner.status_porcelain)
                await self.send_json({"type": "status", "files": files})
            elif msg_type == "add":
                paths = content.get("paths") or []
                if content.get("all"):
                    proc = await asyncio.to_thread(runner.add, ["."])
                elif paths:
                    proc = await asyncio.to_thread(runner.add, paths)
                else:
                    await self.send_json({"type": "error", "code": "invalid_request", "message": "paths or all required"})
                    return
                await self.send_json(
                    {
                        "type": "add",
                        "ok": proc.returncode == 0,
                        "stdout": proc.stdout,
                        "stderr": proc.stderr,
                    }
                )
            elif msg_type == "stash":
                message = content.get("message", "WIP")
                proc = await asyncio.to_thread(runner.stash, message)
                await self.send_json(
                    {
                        "type": "stash",
                        "ok": proc.returncode == 0,
                        "stdout": proc.stdout,
                        "stderr": proc.stderr,
                    }
                )
            elif msg_type == "commit":
                message = content.get("message", "")
                if not message.strip():
                    await self.send_json({"type": "error", "code": "invalid_request", "message": "message required"})
                    return
                proc = await asyncio.to_thread(runner.commit, message)
                await self.send_json(
                    {
                        "type": "commit",
                        "ok": proc.returncode == 0,
                        "stdout": proc.stdout,
                        "stderr": proc.stderr,
                    }
                )
            elif msg_type in ("log_graph", "graph"):
                proc = await asyncio.to_thread(
                    runner.run,
                    "log",
                    "--oneline",
                    "--graph",
                    "--decorate",
                    "--all",
                )
                lines = [line for line in proc.stdout.splitlines() if line.strip()]
                await self.send_json(
                    {
                        "type": "log_graph",
                        "ok": proc.returncode == 0,
                        "lines": lines,
                        "stderr": proc.stderr,
                    }
                )
            elif msg_type == "discard":
                paths = content.get("paths") or []
                if not paths:
                    await self.send_json({"type": "error", "code": "invalid_request", "message": "paths required"})
                    return
                proc = await asyncio.to_thread(runner.discard, paths)
                await self.send_json(
                    {
                        "type": "discard",
                        "ok": proc.returncode == 0,
                        "stdout": proc.stdout,
                        "stderr": proc.stderr,
                    }
                )
            elif msg_type == "branches":
                data = await asyncio.to_thread(runner.branches)
                await self.send_json({"type": "branches", **data})
            elif msg_type == "checkout":
                branch = content.get("branch", "")
                if not branch:
                    await self.send_json({"type": "error", "code": "invalid_request", "message": "branch required"})
                    return
                proc = await asyncio.to_thread(runner.checkout, branch)
                await self.send_json(
                    {
                        "type": "checkout",
                        "ok": proc.returncode == 0,
                        "stdout": proc.stdout,
                        "stderr": proc.stderr,
                    }
                )
            elif msg_type == "log":
                limit = int(content.get("limit", 20))
                commits = await asyncio.to_thread(runner.log, limit)
                await self.send_json({"type": "log", "commits": commits})
            else:
                await self.send_json({"type": "error", "code": "unknown_command", "message": f"Unknown type {msg_type}"})
        except Exception as exc:
            await self.send_json({"type": "error", "code": "git_error", "message": str(exc)})

    async def _resolve_workspace(self, content):
        workspace_id = content.get("workspace_id")
        if workspace_id is None and self.scope.get("workspace") is not None:
            return self.scope["workspace"]
        if workspace_id is None:
            return None
        from channels.db import database_sync_to_async

        @database_sync_to_async
        def _fetch():
            try:
                return Workspace.objects.get(
                    id=int(workspace_id),
                    device_id=self.device.id,
                    is_active=True,
                )
            except (Workspace.DoesNotExist, TypeError, ValueError):
                return None

        return await _fetch()

    async def send_json(self, content):
        await self.send(text_data=json.dumps(content))
