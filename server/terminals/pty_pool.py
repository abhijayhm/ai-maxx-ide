"""Reuse idle shells; spawn when busy; discard dead processes from memory."""

from __future__ import annotations

import threading
from collections import defaultdict

from terminals.pty_manager import PtyManager, PtyProtocol

_MAX_IDLE_PER_KEY = 4


class PtyPool:
    _lock = threading.Lock()
    _idle: dict[tuple[str, str], list[PtyProtocol]] = defaultdict(list)
    _leased: set[int] = set()

    @classmethod
    def acquire_sync(
        cls,
        shell: str,
        cwd: str,
        cols: int,
        rows: int,
    ) -> PtyProtocol:
        key = (shell, cwd)
        with cls._lock:
            while cls._idle[key]:
                pty = cls._idle[key].pop()
                if pty.isalive():
                    cls._leased.add(pty.pid)
                    pty.set_size(cols, rows)
                    return pty
                PtyManager.kill(pty.pid)

            pty = PtyManager.spawn_sync(shell, cwd, cols, rows)
            cls._leased.add(pty.pid)
            return pty

    @classmethod
    async def acquire(cls, shell: str, cwd: str, cols: int, rows: int) -> PtyProtocol:
        import asyncio

        return await asyncio.to_thread(cls.acquire_sync, shell, cwd, cols, rows)

    @classmethod
    def release_sync(cls, pid: int | None, *, destroy: bool = False) -> None:
        if pid is None:
            return
        with cls._lock:
            cls._leased.discard(pid)
            pty = PtyManager.get(pid)
            if pty is None:
                return
            if destroy or not pty.isalive():
                PtyManager.kill(pid)
                return
            shell = getattr(pty, "shell", "powershell")
            cwd = getattr(pty, "cwd", "")
            key = (shell, cwd)
            if len(cls._idle[key]) >= _MAX_IDLE_PER_KEY:
                PtyManager.kill(pid)
            else:
                cls._idle[key].append(pty)

    @classmethod
    async def release(cls, pid: int | None, *, destroy: bool = False) -> None:
        import asyncio

        await asyncio.to_thread(cls.release_sync, pid, destroy=destroy)

    @classmethod
    def discard_all_idle(cls) -> None:
        with cls._lock:
            for ptys in cls._idle.values():
                for pty in ptys:
                    PtyManager.kill(pty.pid)
            cls._idle.clear()
