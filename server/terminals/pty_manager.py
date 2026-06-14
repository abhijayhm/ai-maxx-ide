"""PTY manager with FakePty for tests and subprocess fallback."""

import asyncio
import base64
import os
import subprocess
import threading
import time
from typing import Protocol


class PtyProtocol(Protocol):
    pid: int | None

    def write(self, data: bytes) -> None: ...
    def read(self, size: int = 4096) -> bytes: ...
    def set_size(self, cols: int, rows: int) -> None: ...
    def isalive(self) -> bool: ...
    def kill(self) -> None: ...


class FakePty:
    """In-memory PTY for tests."""

    _counter = 1000
    _instances: dict[int, "FakePty"] = {}

    def __init__(self, shell: str, cwd: str, cols: int, rows: int):
        FakePty._counter += 1
        self.pid = FakePty._counter
        self.shell = shell
        self.cwd = cwd
        self.cols = cols
        self.rows = rows
        self._buffer = bytearray()
        self._alive = True
        FakePty._instances[self.pid] = self

    def write(self, data: bytes) -> None:
        self._buffer.extend(data)
        text = data.decode("utf-8", errors="replace").strip()
        if text == "exit":
            self._alive = False

    def read(self, size: int = 4096) -> bytes:
        if self._buffer:
            out = bytes(self._buffer[:size])
            del self._buffer[: len(out)]
            return out
        if not self._alive:
            return b""
        return f"[{self.shell}@{self.cwd}]$ ".encode()

    def set_size(self, cols: int, rows: int) -> None:
        self.cols = cols
        self.rows = rows

    def isalive(self) -> bool:
        return self._alive

    def kill(self) -> None:
        self._alive = False
        FakePty._instances.pop(self.pid, None)


class SubprocessPty:
    """Subprocess pipe fallback with a background reader (non-blocking reads)."""

    def __init__(self, proc: subprocess.Popen, pid: int):
        self._proc = proc
        self.pid = pid
        self._buffer = bytearray()
        self._lock = threading.Lock()
        self._alive = True
        self._reader = threading.Thread(target=self._read_loop, daemon=True)
        self._reader.start()

    def _read_loop(self) -> None:
        stdout = self._proc.stdout
        while self._alive and self._proc.poll() is None and stdout is not None:
            try:
                chunk = stdout.read(4096)
            except (OSError, ValueError):
                break
            if chunk:
                with self._lock:
                    self._buffer.extend(chunk)
            else:
                time.sleep(0.05)
        self._alive = False

    def write(self, data: bytes) -> None:
        if self._proc.stdin:
            self._proc.stdin.write(data)
            self._proc.stdin.flush()

    def read(self, size: int = 4096) -> bytes:
        with self._lock:
            if self._buffer:
                out = bytes(self._buffer[:size])
                del self._buffer[: len(out)]
                return out
        return b""

    def set_size(self, cols: int, rows: int) -> None:
        pass

    def isalive(self) -> bool:
        return self._alive and self._proc.poll() is None

    def kill(self) -> None:
        self._alive = False
        self._proc.kill()
        try:
            self._proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass


class PtyManager:
    _active: dict[int, PtyProtocol] = {}

    @classmethod
    def _use_fake(cls) -> bool:
        return os.environ.get("TERMINAL_PTY_BACKEND", "").lower() == "fake"

    @classmethod
    async def spawn(cls, shell: str, cwd: str, cols: int, rows: int) -> PtyProtocol:
        return await asyncio.to_thread(cls._spawn_sync, shell, cwd, cols, rows)

    @classmethod
    def _spawn_sync(cls, shell: str, cwd: str, cols: int, rows: int) -> PtyProtocol:
        if cls._use_fake():
            pty = FakePty(shell, cwd, cols, rows)
            cls._active[pty.pid] = pty
            return pty

        try:
            import winpty  # type: ignore

            proc = winpty.PtyProcess.spawn(
                f"{shell}.exe" if shell in ("powershell", "cmd") else shell,
                cwd=cwd,
                dimensions=(rows, cols),
            )
            pty = _WinPtyWrapper(proc)
            cls._active[pty.pid] = pty
            return pty
        except ImportError:
            pass

        if shell == "powershell":
            cmd = ["powershell.exe", "-NoLogo", "-NoProfile"]
        elif shell == "cmd":
            cmd = ["cmd.exe"]
        else:
            cmd = [shell]

        proc = subprocess.Popen(
            cmd,
            cwd=cwd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=False,
        )
        pty = SubprocessPty(proc, proc.pid)
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


class _WinPtyWrapper:
    def __init__(self, proc):
        self._proc = proc
        self.pid = proc.pid if hasattr(proc, "pid") else os.getpid()

    def write(self, data: bytes) -> None:
        self._proc.write(data.decode("utf-8", errors="replace"))

    def read(self, size: int = 4096) -> bytes:
        try:
            return self._proc.read(size).encode("utf-8", errors="replace")
        except EOFError:
            return b""

    def set_size(self, cols: int, rows: int) -> None:
        if hasattr(self._proc, "setwinsize"):
            self._proc.setwinsize(rows, cols)

    def isalive(self) -> bool:
        return self._proc.isalive()

    def kill(self) -> None:
        if self._proc.isalive():
            self._proc.terminate()
