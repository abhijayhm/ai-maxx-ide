import asyncio
import base64
import json
import sys
import time

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from django.utils import timezone

from core.models import DeviceIdentifier
from terminals.io_service import list_terminal_io, save_terminal_io
from terminals.models import Terminal, TerminalIODirection, TerminalStatus
from terminals.output_format import format_terminal_stdout, sanitize_terminal_output
from terminals.pty_pool import PtyPool
from terminals.services import close_stale_terminals


def _terminal_log(session_id, message: str) -> None:
    print(f"[terminal:{session_id}] {message}", file=sys.stderr, flush=True)


def _preview_bytes(data: bytes, limit: int = 160) -> str:
    text = data.decode("utf-8", errors="replace").replace("\r", "\\r").replace("\n", "\\n")
    if len(text) > limit:
        return f"{text[:limit]}…"
    return text


@database_sync_to_async
def get_terminal(session_id, device_id, workspace_id):
    try:
        return Terminal.objects.select_related("workspace").get(
            id=session_id,
            device_id=device_id,
            workspace_id=workspace_id,
        )
    except Terminal.DoesNotExist:
        return None


def _touch_terminal(terminal):
    terminal.last_used = timezone.now()
    terminal.save(update_fields=["last_used"])


touch_terminal = database_sync_to_async(_touch_terminal, thread_sensitive=False)


def _set_terminal_pid(terminal, pid):
    terminal.pid = pid
    terminal.status = TerminalStatus.ACTIVE
    terminal.last_used = timezone.now()
    terminal.save(update_fields=["pid", "status", "last_used"])


set_terminal_pid = database_sync_to_async(_set_terminal_pid, thread_sensitive=False)


def _clear_terminal_pid(terminal):
    terminal.pid = None
    terminal.save(update_fields=["pid"])


clear_terminal_pid = database_sync_to_async(_clear_terminal_pid, thread_sensitive=False)


@database_sync_to_async
def run_close_stale(device_id, workspace_id):
    device = DeviceIdentifier.objects.get(id=device_id)
    return close_stale_terminals(device=device, workspace_id=workspace_id)


def _chunk_has_content(data: bytes) -> bool:
    return bool(sanitize_terminal_output(data).strip())


class TerminalConsumer(AsyncWebsocketConsumer):
    """Interactive terminal over WebSocket — pooled shell per connection, streaming I/O."""

    _QUIET_SECONDS = 0.6
    _MIN_BATCH_SECONDS = 0.4
    _NO_OUTPUT_GRACE = 3.0
    _COMMAND_TIMEOUT = 120.0

    async def connect(self):
        self.session_id = self.scope["url_route"]["kwargs"]["session_id"]
        self.device = self.scope.get("device")
        self.workspace = self.scope.get("workspace")
        self.terminal = None
        self.pty = None
        self._transcript = bytearray()
        self._pump_task = None
        self._batch_watch_task = None
        self._command_active = False
        self._batch_closing = False
        self._last_output_at = 0.0
        self._command_started_at = 0.0
        self._batch_output = bytearray()
        self._batch_command = ""
        self._batch_had_content = False
        self._send_lock = asyncio.Lock()
        self._io_lock = asyncio.Lock()
        self.authenticated = self.scope.get("ws_authenticated", False)

        _terminal_log(self.session_id, "connect requested")
        if self.authenticated and self.device:
            await run_close_stale(self.device.id, self.workspace.id if self.workspace else None)
            await self.accept()
            await self._attach()
        else:
            await self.accept()
            _terminal_log(self.session_id, "awaiting auth message")

    async def receive(self, text_data=None, bytes_data=None):
        if text_data is None:
            return
        try:
            content = json.loads(text_data)
        except json.JSONDecodeError:
            _terminal_log(self.session_id, "invalid JSON from client")
            await self.send_json({"type": "error", "code": "invalid_json", "message": "Invalid JSON"})
            return

        msg_type = content.get("type")
        _terminal_log(self.session_id, f"recv type={msg_type}")

        if msg_type == "auth":
            await self._handle_auth(content)
            return

        if not self.authenticated:
            await self.close(code=4401)
            return

        if msg_type in ("execute", "input") and self.terminal:
            await self._handle_execute(content)
        elif msg_type == "resize" and self.pty and self.terminal:
            cols = content.get("cols", 80)
            rows = content.get("rows", 24)
            _terminal_log(self.session_id, f"resize cols={cols} rows={rows}")
            await asyncio.to_thread(self.pty.set_size, cols, rows)
            self.terminal.cols = cols
            self.terminal.rows = rows
            await touch_terminal(self.terminal)

    def _line_ending(self) -> bytes:
        shell = (self.terminal.shell if self.terminal else "").lower()
        if shell in ("cmd", "powershell", "pwsh"):
            return b"\r\n"
        return b"\n"

    def _normalize_payload(self, data: bytes) -> bytes:
        """Windows shells need CRLF — lone LF only moves the cursor, does not run."""
        line_end = self._line_ending()
        if data.endswith(b"\r\n"):
            return data
        if data.endswith(b"\n"):
            if line_end == b"\r\n":
                return data[:-1] + line_end
            return data
        if data.endswith(b"\r"):
            return data + b"\n"
        return data + line_end

    async def _handle_execute(self, content):
        if self._command_active:
            _terminal_log(self.session_id, "execute rejected — previous batch still active")
            await self._finish_batch(
                error_code="batch_busy",
                error_message="Previous command still running",
            )
            return

        if not self.terminal or self.terminal.status == TerminalStatus.CLOSED:
            _terminal_log(self.session_id, "execute rejected — terminal closed")
            await self._finish_batch(
                error_code="terminal_closed",
                error_message="Terminal is closed",
            )
            return

        if not self.pty or not self.pty.isalive():
            _terminal_log(self.session_id, "pty dead/missing — reacquiring")
            await self._reacquire_pty()
            if not self.pty:
                _terminal_log(self.session_id, "pty reacquire failed")
                await self._finish_batch(
                    error_code="shell_unavailable",
                    error_message="Could not start shell",
                )
                return

        raw = content.get("data", "")
        if not raw:
            _terminal_log(self.session_id, "execute rejected — empty payload")
            await self._finish_batch(
                error_code="empty_payload",
                error_message="Command payload is required",
            )
            return

        try:
            data = base64.b64decode(raw)
        except Exception:
            _terminal_log(self.session_id, "execute rejected — invalid base64")
            await self._finish_batch(
                error_code="invalid_payload",
                error_message="Invalid base64 payload",
            )
            return

        _terminal_log(
            self.session_id,
            f"execute bytes={len(data)} preview={_preview_bytes(data)!r} pid={getattr(self.pty, 'pid', None)}",
        )

        await save_terminal_io(self.terminal.id, TerminalIODirection.INPUT, raw)
        await touch_terminal(self.terminal)

        self._command_active = True
        self._batch_output = bytearray()
        self._batch_command = data.decode("utf-8", errors="replace").strip()
        self._batch_had_content = False
        self._command_started_at = time.monotonic()
        self._last_output_at = self._command_started_at
        await self.send_json({"type": "batch_started"})
        _terminal_log(self.session_id, "sent batch_started")
        self._start_batch_watch()

        payload = self._normalize_payload(data)

        try:
            await asyncio.to_thread(self.pty.write, payload)
            _terminal_log(
                self.session_id,
                f"wrote {len(payload)} bytes to pty preview={_preview_bytes(payload)!r}",
            )
        except Exception as exc:
            _terminal_log(self.session_id, f"pty write failed: {exc!r}")
            await PtyPool.release(self.pty.pid, destroy=True)
            self.pty = None
            await clear_terminal_pid(self.terminal)
            await self._finish_batch(
                error_code="batch_failed",
                error_message=str(exc),
            )
            return

        await touch_terminal(self.terminal)

    def _start_batch_watch(self):
        if self._batch_watch_task:
            self._batch_watch_task.cancel()
        self._batch_watch_task = asyncio.create_task(self._watch_batch())

    def _stop_batch_watch(self):
        task = self._batch_watch_task
        self._batch_watch_task = None
        if task and task is not asyncio.current_task():
            task.cancel()

    async def _watch_batch(self):
        """Detect batch completion even when pty.read() would block."""
        try:
            while self._command_active:
                await asyncio.sleep(0.05)
                if not self._command_active:
                    return
                elapsed_total = time.monotonic() - self._command_started_at
                if elapsed_total >= self._COMMAND_TIMEOUT:
                    _terminal_log(
                        self.session_id,
                        f"batch timed out after {elapsed_total:.1f}s — completing",
                    )
                    await self._complete_batch_success(timed_out=True)
                    return

                if not self._batch_output:
                    if elapsed_total >= self._NO_OUTPUT_GRACE:
                        _terminal_log(
                            self.session_id,
                            f"batch no output after {elapsed_total:.2f}s — completing",
                        )
                        await self._complete_batch_success()
                    continue

                if not self._batch_had_content:
                    if elapsed_total >= self._NO_OUTPUT_GRACE:
                        _terminal_log(
                            self.session_id,
                            f"batch only noise after {elapsed_total:.2f}s — completing",
                        )
                        await self._complete_batch_success()
                    continue

                elapsed_quiet = time.monotonic() - self._last_output_at
                if (
                    elapsed_quiet >= self._QUIET_SECONDS
                    and elapsed_total >= self._MIN_BATCH_SECONDS
                ):
                    _terminal_log(
                        self.session_id,
                        f"batch quiet for {elapsed_quiet:.2f}s — completing "
                        f"(out_bytes={len(self._batch_output)})",
                    )
                    await self._complete_batch_success()
                    return
        except asyncio.CancelledError:
            pass

    async def _complete_batch_success(self, *, timed_out: bool = False):
        if not self._command_active:
            return
        self._stop_batch_watch()
        self._batch_closing = True
        # Let the output pump drain pywinpty before we snapshot the batch.
        await asyncio.sleep(0.35)
        async with self._io_lock:
            batch_bytes = bytes(self._batch_output)
            self._command_active = False
            self._batch_closing = False
            self._batch_output = bytearray(batch_bytes)

        frame: dict = {"type": "batch_complete", "exit_code": 0}
        if timed_out:
            frame["timed_out"] = True
        if batch_bytes:
            frame["data"] = base64.b64encode(batch_bytes).decode("ascii")
            display = format_terminal_stdout(batch_bytes, self._batch_command)
            if display:
                frame["text"] = display
        await self.send_json(frame)
        _terminal_log(
            self.session_id,
            f"sent batch_complete timed_out={timed_out} batch_out={len(batch_bytes)} "
            f"preview={_preview_bytes(batch_bytes)!r} text={frame.get('text', '')!r}",
        )
        await self._persist_batch_output()
        if self.terminal:
            await touch_terminal(self.terminal)

    async def _finish_batch(
        self,
        *,
        error_code: str | None = None,
        error_message: str | None = None,
    ):
        self._command_active = False
        self._batch_closing = False
        self._stop_batch_watch()
        if error_code:
            _terminal_log(self.session_id, f"batch error {error_code}: {error_message}")
            await self.send_json(
                {"type": "error", "code": error_code, "message": error_message or error_code}
            )
        await self.send_json({"type": "batch_complete", "exit_code": 1})
        _terminal_log(self.session_id, "sent batch_complete (error path)")

    async def _persist_batch_output(self):
        if not self._batch_output or not self.terminal:
            return
        encoded = base64.b64encode(bytes(self._batch_output)).decode("ascii")
        await save_terminal_io(self.terminal.id, TerminalIODirection.OUTPUT, encoded)

    async def _pump_output(self):
        _terminal_log(self.session_id, "output pump started")
        while self.pty and self.pty.isalive():
            data = await asyncio.to_thread(self.pty.read, 4096)
            if data:
                track_batch = False
                async with self._io_lock:
                    self._transcript.extend(data)
                    if self._command_active or self._batch_closing:
                        self._batch_output.extend(data)
                        if _chunk_has_content(data):
                            self._batch_had_content = True
                            self._last_output_at = time.monotonic()
                        track_batch = True
                encoded = base64.b64encode(data).decode("ascii")
                if track_batch:
                    _terminal_log(
                        self.session_id,
                        f"pump batch bytes={len(data)} total={len(self._batch_output)} "
                        f"preview={_preview_bytes(data)!r}",
                    )
                await self.send_json({"type": "output", "data": encoded})
            else:
                await asyncio.sleep(0.05)

        _terminal_log(self.session_id, "output pump ended — pty not alive")
        if self.terminal:
            await clear_terminal_pid(self.terminal)
        await self.send_json({"type": "exit", "code": 0})

    async def _reacquire_pty(self):
        if not self.terminal:
            return
        self.pty = await PtyPool.acquire(
            self.terminal.shell,
            self.terminal.cwd,
            self.terminal.cols,
            self.terminal.rows,
        )
        await set_terminal_pid(self.terminal, self.pty.pid)
        _terminal_log(
            self.session_id,
            f"acquired pty pid={self.pty.pid} shell={self.terminal.shell} cwd={self.terminal.cwd}",
        )

    async def _history_bytes(self) -> bytes:
        if not self.terminal:
            return b""
        history = await list_terminal_io(self.terminal.id)
        buffer = bytearray()
        for line in history:
            if line.direction == TerminalIODirection.OUTPUT and line.data:
                buffer.extend(base64.b64decode(line.data))
        return bytes(buffer)

    async def _send_output_full(self):
        encoded = base64.b64encode(bytes(self._transcript)).decode("ascii")
        await self.send_json({"type": "output_full", "data": encoded})

    async def _handle_auth(self, content):
        from django.conf import settings

        api_key = content.get("api_key", "")
        device_hash = content.get("device_hash", "")
        workspace_id = content.get("workspace_id")

        if api_key != settings.API_KEY:
            _terminal_log(self.session_id, "auth failed — invalid api key")
            await self.send_json({"type": "error", "code": "invalid_api_key", "message": "Invalid API key"})
            await self.close(code=4401)
            return

        device = await database_sync_to_async(
            lambda: DeviceIdentifier.objects.filter(hash=device_hash, is_active=True).first()
        )()
        if not device:
            _terminal_log(self.session_id, "auth failed — device not registered")
            await self.send_json({"type": "error", "code": "device_not_registered", "message": "Device not registered"})
            await self.close(code=4401)
            return

        self.device = device
        self.authenticated = True
        _terminal_log(self.session_id, f"auth ok device={device.id}")

        if workspace_id:
            from core.models import Workspace

            self.workspace = await database_sync_to_async(
                lambda: Workspace.objects.filter(
                    id=workspace_id, device=device, is_active=True
                ).first()
            )()

        await run_close_stale(device.id, self.workspace.id if self.workspace else None)
        await self._attach()

    async def _attach(self):
        if not self.workspace:
            _terminal_log(self.session_id, "attach failed — workspace required")
            await self.send_json({"type": "error", "code": "workspace_required", "message": "Workspace required"})
            await self.close(code=4401)
            return

        self.terminal = await get_terminal(
            self.session_id, self.device.id, self.workspace.id
        )
        if not self.terminal:
            _terminal_log(self.session_id, "attach failed — terminal not found")
            await self.send_json({"type": "error", "code": "not_found", "message": "Terminal not found"})
            await self.close(code=4404)
            return

        if self.terminal.status == TerminalStatus.CLOSED:
            _terminal_log(self.session_id, "attach failed — terminal closed (idle)")
            await self.send_json(
                {"type": "error", "code": "terminal_closed", "message": "idle timeout"}
            )
            await self.close(code=4403)
            return

        await self._reacquire_pty()
        backend = type(self.pty).__name__ if self.pty else "none"
        _terminal_log(self.session_id, f"pty backend={backend}")

        ready = {
            "type": "ready",
            "cols": self.terminal.cols,
            "rows": self.terminal.rows,
            "cwd": self.terminal.cwd,
            "shell": self.terminal.shell,
            "status": self.terminal.status,
            "pid": self.terminal.pid,
        }
        await self.send_json(ready)
        await self.send_json({"type": "attached", **{k: v for k, v in ready.items() if k != "type"}})
        _terminal_log(
            self.session_id,
            f"attached shell={self.terminal.shell} cwd={self.terminal.cwd} pid={self.terminal.pid}",
        )

        self._transcript = bytearray(await self._history_bytes())
        await self._send_output_full()
        self._pump_task = asyncio.create_task(self._pump_output())

    async def disconnect(self, code):
        _terminal_log(self.session_id, f"disconnect code={code}")
        self._stop_batch_watch()
        if self._pump_task:
            self._pump_task.cancel()
        if self.pty:
            await PtyPool.release(self.pty.pid, destroy=False)
            self.pty = None
        if self.terminal:
            await clear_terminal_pid(self.terminal)

    async def send_json(self, content):
        msg_type = content.get("type", "?")
        if msg_type not in ("output",):
            _terminal_log(self.session_id, f"send type={msg_type}")
        async with self._send_lock:
            await self.send(text_data=json.dumps(content))
