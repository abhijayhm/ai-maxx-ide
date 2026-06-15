"""Launch whitelisted Windows maintenance scripts."""

from __future__ import annotations

import logging
import subprocess
import sys
import threading
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from standalone.bootstrap import active_scripts_dir, repo_root

logger = logging.getLogger(__name__)

ALLOWED_SCRIPTS: dict[str, dict[str, Any]] = {
    "setup_cloudflare_tunnel": {
        "label": "Setup Cloudflare tunnel",
        "file": "setup_cloudflare_tunnel.bat",
        "description": "Install/configure cloudflared for SERVER_DOMAIN (may need admin).",
        "section": "tunnel",
    },
    "start_services": {
        "label": "Start tunnel + server",
        "file": "start_services.bat",
        "description": "Start cloudflared (if needed) and the server on SERVER_PORT.",
        "section": "tunnel",
    },
    "install_startup_task": {
        "label": "Install startup scheduler",
        "file": "install_startup_task.bat",
        "description": "Run start_services.bat at Windows logon (may need admin).",
        "section": "schedulers",
    },
    "install_watchdog_task": {
        "label": "Install watchdog scheduler",
        "file": "install_watchdog_task.bat",
        "description": "Every minute, silently ensure tunnel and server are running; restart if down.",
        "section": "schedulers",
    },
    "remove_schedulers": {
        "label": "Shutdown & remove schedulers",
        "file": "remove_schedulers.bat",
        "description": "Stop aimaxx-ide.exe and delete startup/watchdog tasks.",
        "section": "schedulers",
        "close_dashboard": True,
    },
}


@dataclass
class ScriptJob:
    script_id: str
    pid: int | None
    log_path: Path
    started_at: str
    finished_at: str | None = None
    returncode: int | None = None
    error: str | None = None
    _lines: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "script_id": self.script_id,
            "pid": self.pid,
            "log_path": str(self.log_path),
            "started_at": self.started_at,
            "finished_at": self.finished_at,
            "returncode": self.returncode,
            "error": self.error,
            "log_tail": "".join(self._lines[-80:]),
        }


_jobs: dict[str, ScriptJob] = {}
_lock = threading.Lock()


def list_scripts() -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for script_id, meta in ALLOWED_SCRIPTS.items():
        row = {"id": script_id, **meta}
        items.append(row)
    return items


def script_closes_dashboard(script_id: str) -> bool:
    meta = ALLOWED_SCRIPTS.get(script_id) or {}
    return bool(meta.get("close_dashboard"))


def _log_path(script_id: str) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    logs = repo_root() / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    return logs / f"{script_id}-{stamp}.log"


def _reader(job: ScriptJob, proc: subprocess.Popen[str]) -> None:
    assert proc.stdout is not None
    with job.log_path.open("a", encoding="utf-8", errors="replace") as log_file:
        for line in proc.stdout:
            job._lines.append(line)
            log_file.write(line)
    proc.wait()
    job.returncode = proc.returncode
    job.finished_at = datetime.now(timezone.utc).isoformat()


def start_script(script_id: str) -> ScriptJob:
    meta = ALLOWED_SCRIPTS.get(script_id)
    if meta is None:
        raise ValueError(f"Unknown script: {script_id}")

    script_path = active_scripts_dir() / meta["file"]
    if not script_path.is_file():
        raise FileNotFoundError(f"Script not found: {script_path}")

    log_path = _log_path(script_id)
    log_path.write_text("", encoding="utf-8")

    cmd = ["cmd.exe", "/c", str(script_path)]

    creationflags = 0
    if sys.platform == "win32":
        if meta.get("close_dashboard"):
            creationflags = subprocess.CREATE_NO_WINDOW
        else:
            creationflags = subprocess.CREATE_NEW_CONSOLE

    proc = subprocess.Popen(
        cmd,
        cwd=str(repo_root()),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=creationflags,
    )

    job = ScriptJob(
        script_id=script_id,
        pid=proc.pid,
        log_path=log_path,
        started_at=datetime.now(timezone.utc).isoformat(),
    )
    with _lock:
        _jobs[script_id] = job

    thread = threading.Thread(target=_reader, args=(job, proc), daemon=True)
    thread.start()
    logger.info("Started script %s pid=%s log=%s", script_id, proc.pid, log_path)
    return job


def get_job(script_id: str) -> ScriptJob | None:
    with _lock:
        return _jobs.get(script_id)
