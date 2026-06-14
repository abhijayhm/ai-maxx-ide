import sys


def default_terminal_shell() -> str:
    """Windows → cmd; other platforms → PowerShell."""
    return "cmd" if sys.platform == "win32" else "powershell"
