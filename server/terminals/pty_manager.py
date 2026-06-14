"""Windows interactive shells via pywinpty (ConPTY); FakePty for tests."""

from __future__ import annotations

import asyncio
import os
import sys
import threading
import time
from typing import Protocol

_PYWINPTY_IMPORT_ERROR: Exception | None = None
try:
    from winpty import PtyProcess as _PtyProcess
except ImportError as exc:
    _PtyProcess = None
    _PYWINPTY_IMPORT_ERROR = exc


class PtyProtocol(Protocol):
    pid: int | None

    def write(self, data: bytes) -> None: ...
    def read(self, size: int = 4096) -> bytes: ...
    def set_size(self, cols: int, rows: int) -> None: ...
    def isalive(self) -> bool: ...
    def kill(self) -> None: ...


def shell_argv(shell: str) -> list[str]:
    """Executable + args for an interactive shell session."""
    key = shell.lower()
    if key == "cmd":
        return ["cmd.exe"]
    if key in ("powershell", "pwsh"):
        return ["powershell.exe", "-NoLogo", "-NoProfile"]
    if shell.endswith((".exe", ".cmd", ".bat")):
        return [shell]
    return [f"{shell}.exe"]


def _require_pywinpty() -> type:
    if _PtyProcess is None:
        raise RuntimeError(
            "pywinpty is required for interactive terminals on Windows. "
            "Install server dependencies: pip install -r server/requirements.txt "
            f"(import error: {_PYWINPTY_IMPORT_ERROR})"
        ) from _PYWINPTY_IMPORT_ERROR
    return _PtyProcess


class FakePty:
    """In-memory PTY for tests."""

    _counter = 1000
    _instances: dict[int, FakePty] = {}

    def __init__(self, shell: str, cwd: str, cols: int, rows: int):
        FakePty._counter += 1
        self.pid = FakePty._counter
        self.shell = shell
        self.cwd = cwd
        self.cols = cols
        self.rows = rows
        self._out_buffer = bytearray()
        self._alive = True
        FakePty._instances[self.pid] = self
        self._out_buffer.extend(f"[{self.shell}@{self.cwd}]$ ".encode())

    def write(self, data: bytes) -> None:
        text = data.decode("utf-8", errors="replace")
        self._out_buffer.extend(data)
        stripped = text.strip()
        if stripped.lower().startswith("echo "):
            self._out_buffer.extend(f"{stripped[5:].strip()}\r\n".encode())
        if stripped == "exit":
            self._alive = False

    def read(self, size: int = 4096) -> bytes:
        if self._out_buffer:
            out = bytes(self._out_buffer[:size])
            del self._out_buffer[: len(out)]
            return out
        if not self._alive:
            return b""
        return b""

    def set_size(self, cols: int, rows: int) -> None:
        self.cols = cols
        self.rows = rows

    def isalive(self) -> bool:
        return self._alive

    def kill(self) -> None:
        self._alive = False
        FakePty._instances.pop(self.pid, None)


class PywinptySession:
    """Background-drained pywinpty session — non-blocking reads for the WS pump."""

    def __init__(self, proc, *, shell: str, cwd: str):
        self._proc = proc
        self.shell = shell
        self.cwd = cwd
        self.pid = proc.pid
        self._buffer = bytearray()
        self._lock = threading.Lock()
        self._alive = True
        self._reader = threading.Thread(target=self._read_loop, name=f"pywinpty-{self.pid}", daemon=True)
        self._reader.start()

    def _read_loop(self) -> None:
        while self._alive and self._proc.isalive():
            try:
                chunk = self._proc.read(4096)
            except EOFError:
                break
            except Exception:
                break
            if not chunk:
                time.sleep(0.02)
                continue
            data = chunk if isinstance(chunk, bytes) else str(chunk).encode("utf-8", errors="replace")
            with self._lock:
                self._buffer.extend(data)

        self._alive = False

    def write(self, data: bytes) -> None:
        if not self._alive:
            raise RuntimeError("Pty is closed")
        text = data.decode("utf-8", errors="replace")
        try:
            self._proc.write(text)
        except EOFError as exc:
            self._alive = False
            raise RuntimeError("Pty is closed") from exc

    def read(self, size: int = 4096) -> bytes:
        with self._lock:
            if self._buffer:
                out = bytes(self._buffer[:size])
                del self._buffer[: len(out)]
                return out
        return b""

    def set_size(self, cols: int, rows: int) -> None:
        if hasattr(self._proc, "setwinsize"):
            self._proc.setwinsize(rows, cols)

    def isalive(self) -> bool:
        return self._alive and self._proc.isalive()

    def kill(self) -> None:
        self._alive = False
        if self._proc.isalive():
            self._proc.terminate(force=True)


class PtyManager:
    _active: dict[int, PtyProtocol] = {}

    @classmethod
    def _use_fake(cls) -> bool:
        return os.environ.get("TERMINAL_PTY_BACKEND", "").lower() == "fake"

    @classmethod
    async def spawn(cls, shell: str, cwd: str, cols: int, rows: int) -> PtyProtocol:
        return await asyncio.to_thread(cls.spawn_sync, shell, cwd, cols, rows)

    @classmethod
    def spawn_sync(cls, shell: str, cwd: str, cols: int, rows: int) -> PtyProtocol:
        if cls._use_fake():
            pty = FakePty(shell, cwd, cols, rows)
            cls._active[pty.pid] = pty
            return pty

        if sys.platform != "win32":
            raise RuntimeError(
                "Interactive terminals are only supported on Windows in this build."
            )

        PtyProcess = _require_pywinpty()
        argv = shell_argv(shell)
        proc = PtyProcess.spawn(argv, cwd=cwd, dimensions=(rows, cols))
        pty = PywinptySession(proc, shell=shell, cwd=cwd)
        cls._active[pty.pid] = pty
        return pty

    @classmethod
    def get(cls, pid: int | None) -> PtyProtocol | None:
        if pid is None:
            return None
        return cls._active.get(pid)

    @classmethod
    def kill(cls, pid: int | None) -> None:
        if pid is None:
            return
        pty = cls._active.pop(pid, None)
        if pty:
            pty.kill()
        FakePty._instances.pop(pid, None)

    @classmethod
    async def run_batch(
        cls,
        *,
        shell: str,
        cwd: str,
        cols: int,
        rows: int,
        data: bytes,
        max_wait: float = 30.0,
        quiet: float = 0.25,
    ) -> bytes:
        """Spawn a shell, write one payload, read until quiet, then tear down."""

        def _run() -> bytes:
            pty = cls.spawn_sync(shell, cwd, cols, rows)
            try:
                line_end = b"\r\n" if shell.lower() in ("cmd", "powershell", "pwsh") else b"\n"
                payload = data if data.endswith((b"\n", b"\r\n")) else data + line_end
                pty.write(payload)
                return cls._collect_output_sync(pty, max_wait=max_wait, quiet=quiet)
            finally:
                cls.kill(pty.pid)

        return await asyncio.to_thread(_run)

    @classmethod
    def _collect_output_sync(
        cls,
        pty: PtyProtocol,
        *,
        max_wait: float = 30.0,
        quiet: float = 0.25,
    ) -> bytes:
        chunks = bytearray()
        deadline = time.monotonic() + max_wait
        quiet_until = None
        while time.monotonic() < deadline:
            data = pty.read(4096)
            if data:
                chunks.extend(data)
                quiet_until = time.monotonic() + quiet
            elif quiet_until is not None and time.monotonic() >= quiet_until:
                break
            else:
                time.sleep(0.05)
        return bytes(chunks)
