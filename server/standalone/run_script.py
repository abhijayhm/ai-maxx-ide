"""Run bundled helper scripts via `exe --run-script <name>`."""

from __future__ import annotations

import runpy
import sys
from pathlib import Path

from standalone.bootstrap import active_scripts_dir, bundled_scripts_dir


def _script_path(name: str) -> Path:
    for base in (active_scripts_dir(), bundled_scripts_dir()):
        path = base / f"{name}.py"
        if path.is_file():
            return path
    raise FileNotFoundError(f"Unknown script: {name}")


def main(argv: list[str] | None = None) -> int:
    args = list(argv if argv is not None else sys.argv[1:])
    if not args:
        print("Usage: --run-script <script_name> [args...]", file=sys.stderr)
        return 2

    name = args[0].removesuffix(".py")
    path = _script_path(name)
    sys.argv = [str(path), *args[1:]]
    runpy.run_path(str(path), run_name="__main__")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
