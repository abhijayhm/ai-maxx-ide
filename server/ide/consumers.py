"""WebSocket consumers: watchdog, ide_search (Aho-Corasick), getbypath, git."""

from __future__ import annotations

import asyncio
import json
import threading
from pathlib import Path

from channels.generic.websocket import AsyncWebsocketConsumer
from django.conf import settings

from core.models import Workspace
from gitapp.runner import get_git_runner
from ide.file_service import file_meta, resolve_workspace_file, stream_workspace_file
from ide.search_service import stream_ide_search
from ide.watchdog_service import exposed_watchdog


def _debug(consumer: str, message: str) -> None:
    print(f"[ide.ws.{consumer}] {message}", flush=True)


class WatchdogConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        if not self.scope.get("ws_authenticated") or self.scope.get("device") is None:
            _debug("watchdog", "connect rejected (unauthenticated)")
            await self.close(code=4401)
            return
        device = self.scope["device"]
        await self.accept()
        _debug("watchdog", f"connected device_id={device.id}")
        self._queue = exposed_watchdog.subscribe()
        self._pump_task = asyncio.create_task(self._pump())

    async def disconnect(self, close_code):
        _debug("watchdog", f"disconnected close_code={close_code}")
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
            _debug("watchdog", "ping")
            await self.send(text_data=json.dumps({"type": "pong"}))


class IdeSearchConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        if not self.scope.get("ws_authenticated") or self.scope.get("device") is None:
            _debug("ide_search", "connect rejected (unauthenticated)")
            await self.close(code=4401)
            return
        self.device = self.scope["device"]
        self._search_task: asyncio.Task | None = None
        await self.accept()
        _debug("ide_search", f"connected device_id={self.device.id}")

    async def disconnect(self, close_code):
        _debug("ide_search", f"disconnected close_code={close_code}")
        if self._search_task is not None:
            self._search_task.cancel()

    async def receive(self, text_data=None, bytes_data=None):
        if text_data is None:
            return
        _debug("ide_search", f"receive raw={text_data!r}")
        try:
            content = json.loads(text_data)
        except json.JSONDecodeError:
            _debug("ide_search", "invalid JSON")
            await self.send_json({"type": "error", "code": "invalid_json", "message": "Invalid JSON"})
            return

        msg_type = content.get("type")
        if msg_type == "cancel":
            _debug("ide_search", "cancel requested")
            if self._search_task is not None:
                self._search_task.cancel()
            await self.send_json({"type": "cancelled"})
            return

        if msg_type != "search":
            _debug("ide_search", f"invalid type={msg_type!r}")
            await self.send_json({"type": "error", "code": "invalid_type", "message": "Expected type search"})
            return

        workspace_id = content.get("workspace_id")
        if workspace_id is None:
            _debug("ide_search", "search missing workspace_id")
            await self.send_json({"type": "error", "code": "workspace_required", "message": "workspace_id required"})
            return

        workspace = await self._get_workspace(workspace_id)
        if workspace is None:
            _debug("ide_search", f"workspace not found workspace_id={workspace_id}")
            await self.send_json({"type": "error", "code": "workspace_not_found", "message": "Workspace not found"})
            return

        if self._search_task is not None and not self._search_task.done():
            _debug("ide_search", "cancelling previous search")
            self._search_task.cancel()

        keyword = content.get("keyword") or content.get("pattern") or ""
        _debug(
            "ide_search",
            f"search workspace_id={workspace.id} keyword={keyword!r} "
            f"match_case={content.get('match_case', False)} match_exact={content.get('match_exact', False)}",
        )
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

        result_count = 0
        try:
            while True:
                item = await queue.get()
                if item is None:
                    break
                if isinstance(item, Exception):
                    raise item
                result_count += 1
                await self.send_json({"type": "result", **item})
            _debug("ide_search", f"search_complete workspace_id={workspace.id} results={result_count}")
            await self.send_json({"type": "search_complete"})
        except asyncio.CancelledError:
            _debug("ide_search", f"search_cancelled workspace_id={workspace.id} results={result_count}")
            await self.send_json({"type": "cancelled"})
        except Exception as exc:
            _debug("ide_search", f"search_failed workspace_id={workspace.id} error={exc!r}")
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


class GetByPathConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        if not self.scope.get("ws_authenticated") or self.scope.get("device") is None:
            _debug("getbypath", "connect rejected (unauthenticated)")
            await self.close(code=4401)
            return
        self.device = self.scope["device"]
        self._read_task: asyncio.Task | None = None
        await self.accept()
        _debug("getbypath", f"connected device_id={self.device.id}")

    async def disconnect(self, close_code):
        _debug("getbypath", f"disconnected close_code={close_code}")
        if self._read_task is not None:
            self._read_task.cancel()

    async def receive(self, text_data=None, bytes_data=None):
        if text_data is None:
            return
        _debug("getbypath", f"receive raw={text_data!r}")
        try:
            content = json.loads(text_data)
        except json.JSONDecodeError:
            _debug("getbypath", "invalid JSON")
            await self.send_json({"type": "error", "code": "invalid_json", "message": "Invalid JSON"})
            return

        msg_type = content.get("type")
        if msg_type == "cancel":
            _debug("getbypath", "cancel requested")
            if self._read_task is not None:
                self._read_task.cancel()
            await self.send_json({"type": "cancelled"})
            return

        if msg_type != "get":
            _debug("getbypath", f"invalid type={msg_type!r}")
            await self.send_json({"type": "error", "code": "invalid_type", "message": "Expected type get"})
            return

        workspace_id = content.get("workspace_id")
        file_path = content.get("path") or ""
        if workspace_id is None:
            await self.send_json({"type": "error", "code": "workspace_required", "message": "workspace_id required"})
            return
        if not str(file_path).strip():
            await self.send_json({"type": "error", "code": "path_required", "message": "path required"})
            return

        workspace = await self._get_workspace(workspace_id)
        if workspace is None:
            await self.send_json({"type": "error", "code": "workspace_not_found", "message": "Workspace not found"})
            return

        if self._read_task is not None and not self._read_task.done():
            self._read_task.cancel()

        self._read_task = asyncio.create_task(self._run_get(workspace, file_path))

    async def _run_get(self, workspace, file_path: str):
        root = Path(workspace.absolute_path)
        resolved = resolve_workspace_file(root, file_path)
        if resolved is None:
            _debug("getbypath", f"file_not_found workspace_id={workspace.id} path={file_path!r}")
            await self.send_json({"type": "error", "code": "file_not_found", "message": "File not found in workspace"})
            return

        try:
            meta = await asyncio.to_thread(file_meta, resolved)
        except OSError as exc:
            await self.send_json({"type": "error", "code": "read_failed", "message": str(exc)})
            return

        await self.send_json({"type": "file_started", "workspace_id": workspace.id, **meta})

        loop = asyncio.get_running_loop()
        queue: asyncio.Queue = asyncio.Queue()

        def worker():
            try:
                for chunk in stream_workspace_file(resolved):
                    loop.call_soon_threadsafe(queue.put_nowait, chunk)
            except Exception as exc:
                loop.call_soon_threadsafe(queue.put_nowait, exc)
            finally:
                loop.call_soon_threadsafe(queue.put_nowait, None)

        threading.Thread(target=worker, daemon=True).start()

        chunk_count = 0
        try:
            while True:
                item = await queue.get()
                if item is None:
                    break
                if isinstance(item, Exception):
                    raise item
                chunk_count += 1
                await self.send_json({"type": "chunk", **item})
            _debug("getbypath", f"file_complete workspace_id={workspace.id} chunks={chunk_count}")
            await self.send_json({"type": "file_complete"})
        except asyncio.CancelledError:
            _debug("getbypath", f"file_cancelled workspace_id={workspace.id} chunks={chunk_count}")
            await self.send_json({"type": "cancelled"})
        except Exception as exc:
            _debug("getbypath", f"file_failed workspace_id={workspace.id} error={exc!r}")
            await self.send_json({"type": "error", "code": "read_failed", "message": str(exc)})

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
            _debug("git", "connect rejected (unauthenticated)")
            await self.close(code=4401)
            return
        self.device = self.scope["device"]
        await self.accept()
        _debug("git", f"connected device_id={self.device.id}")

    async def disconnect(self, close_code):
        _debug("git", f"disconnected close_code={close_code}")

    async def receive(self, text_data=None, bytes_data=None):
        if text_data is None:
            return
        _debug("git", f"receive raw={text_data!r}")
        try:
            content = json.loads(text_data)
        except json.JSONDecodeError:
            _debug("git", "invalid JSON")
            await self.send_json({"type": "error", "code": "invalid_json", "message": "Invalid JSON"})
            return

        msg_type = content.get("type")
        workspace = await self._resolve_workspace(content)
        if workspace is None:
            _debug("git", f"workspace not found type={msg_type!r} workspace_id={content.get('workspace_id')!r}")
            await self.send_json({"type": "error", "code": "workspace_required", "message": "Valid workspace_id required"})
            return

        _debug("git", f"command type={msg_type!r} workspace_id={workspace.id} path={workspace.absolute_path!r}")
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
                _debug("git", f"unknown command type={msg_type!r}")
                await self.send_json({"type": "error", "code": "unknown_command", "message": f"Unknown type {msg_type}"})
        except Exception as exc:
            _debug("git", f"git_error type={msg_type!r} error={exc!r}")
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
