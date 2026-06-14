"""PyInstaller entry point: sync .env, migrate, serve ASGI on :8000."""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path


def _configure_sys_path() -> Path:
    if getattr(sys, "frozen", False):
        server = Path(sys._MEIPASS)
    else:
        server = Path(__file__).resolve().parent.parent
    server_str = str(server)
    if server_str not in sys.path:
        sys.path.insert(0, server_str)
    os.chdir(server_str)
    return server


def _run_script_mode(argv: list[str]) -> int:
    from standalone.run_script import main as run_script_main

    return run_script_main(argv)


def _run_server(host: str, port: int) -> None:
    from standalone.bootstrap import ensure_runtime

    ensure_runtime()

    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

    import django
    from django.core.management import call_command

    django.setup()
    call_command("migrate", "--noinput", verbosity=1)

    import uvicorn

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    logging.getLogger(__name__).info("Starting ai-maxx-ide on http://%s:%s", host, port)
    uvicorn.run(
        "config.asgi:application",
        host=host,
        port=port,
        log_level="info",
        factory=False,
    )


def main(argv: list[str] | None = None) -> int:
    args = list(argv if argv is not None else sys.argv[1:])
    _configure_sys_path()

    if args[:1] == ["--run-script"]:
        return _run_script_mode(args[1:])

    parser = argparse.ArgumentParser(description="ai-maxx-ide standalone server")
    parser.add_argument("--host", default=None, help="Bind host (default from .env BIND_HOST)")
    parser.add_argument("--port", type=int, default=None, help="Bind port (default from .env BIND_PORT)")
    ns = parser.parse_args(args)

    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

    from django.conf import settings

    host = ns.host or settings.BIND_HOST
    port = ns.port or settings.BIND_PORT
    _run_server(host, port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
