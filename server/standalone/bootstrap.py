"""Resolve paths and sync .env for dev vs PyInstaller frozen runs."""

from __future__ import annotations

import logging
import os
import shutil
import sys
from pathlib import Path

logger = logging.getLogger(__name__)


def is_frozen() -> bool:
    return bool(getattr(sys, "frozen", False))


def app_root() -> Path:
    """Directory containing the executable (frozen) or repo root (dev)."""
    if is_frozen():
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent.parent.parent


def runtime_root() -> Path:
    if is_frozen():
        return Path(getattr(sys, "_MEIPASS"))
    return app_root()


def server_dir() -> Path:
    if is_frozen():
        return runtime_root()
    return Path(__file__).resolve().parent.parent


def repo_root() -> Path:
    if is_frozen():
        return app_root()
    return server_dir().parent


def bundled_scripts_dir() -> Path:
    return runtime_root() / "scripts" / "windows"


def active_scripts_dir() -> Path:
    """Scripts visible to .bat files (mirrored beside the exe when frozen)."""
    if is_frozen():
        return app_root() / "scripts" / "windows"
    return repo_root() / "scripts" / "windows"


def _copy_tree(src: Path, dst: Path) -> None:
    if not src.is_dir():
        return
    dst.mkdir(parents=True, exist_ok=True)
    for item in src.iterdir():
        target = dst / item.name
        if item.is_dir():
            shutil.copytree(item, target, dirs_exist_ok=True)
        else:
            shutil.copy2(item, target)


def _write_frozen_python_launcher(scripts_dst: Path) -> None:
    launcher = scripts_dst / "_aimaxx_python.cmd"
    launcher.write_text(
        f'@"{Path(sys.executable).resolve()}" --run-script %*\r\n',
        encoding="utf-8",
    )


def ensure_native_dll_paths() -> None:
    """Help PyInstaller builds load av/ffmpeg and other native wheels on Windows."""
    if not is_frozen() or sys.platform != "win32":
        return
    if not hasattr(os, "add_dll_directory"):
        return

    for directory in (runtime_root(), runtime_root() / "av"):
        if directory.is_dir():
            os.add_dll_directory(str(directory))


def ensure_runtime() -> None:
    """Copy .env, sample.env, scripts, and data dir into the live app folder."""
    ensure_native_dll_paths()
    root = repo_root()
    root.mkdir(parents=True, exist_ok=True)
    (root / "data").mkdir(parents=True, exist_ok=True)
    (root / "logs").mkdir(parents=True, exist_ok=True)

    bundled_sample = runtime_root() / "sample.env"
    app_sample = root / "sample.env"
    if bundled_sample.is_file() and not app_sample.is_file():
        shutil.copy2(bundled_sample, app_sample)

    env_src = app_root() / ".env"
    if not env_src.is_file() and app_sample.is_file():
        shutil.copy2(app_sample, env_src)
        logger.warning("Created %s from sample.env — edit before production use.", env_src)

    dst_env = repo_root() / ".env"
    if env_src.is_file() and env_src.resolve() != dst_env.resolve():
        shutil.copy2(env_src, dst_env)

    if is_frozen():
        scripts_dst = active_scripts_dir()
        _copy_tree(bundled_scripts_dir(), scripts_dst)
        _write_frozen_python_launcher(scripts_dst)

        setup_bat = scripts_dst / "setup_cloudflare_tunnel.bat"
        if setup_bat.is_file():
            text = setup_bat.read_text(encoding="utf-8", errors="replace")
            if "_aimaxx_python.cmd" not in text:
                text = text.replace(
                    'if not defined PY where python >nul 2>&1 && set "PY=python"',
                    'if not defined PY if exist "%SCRIPT_DIR%_aimaxx_python.cmd" set "PY=%SCRIPT_DIR%_aimaxx_python.cmd"\r\n'
                    'if not defined PY where python >nul 2>&1 && set "PY=python"',
                )
                setup_bat.write_text(text, encoding="utf-8")
