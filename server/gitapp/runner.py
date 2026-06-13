"""Git CLI runner — mock-friendly subprocess wrapper."""

import subprocess
from typing import Callable


class GitRunner:
    """Execute git commands in a workspace directory."""

    def __init__(self, cwd: str, runner: Callable | None = None):
        self.cwd = cwd
        self._runner = runner or self._default_runner

    def _default_runner(self, args: list[str], timeout: int = 60) -> subprocess.CompletedProcess:
        cmd = ["git", *args]
        return subprocess.run(
            cmd,
            cwd=self.cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )

    def run(self, *args: str, timeout: int = 60) -> subprocess.CompletedProcess:
        return self._runner(list(args), timeout=timeout)

    def status_porcelain(self) -> list[dict]:
        proc = self.run("status", "--porcelain")
        files = []
        for line in proc.stdout.splitlines():
            if len(line) < 4:
                continue
            status = line[:2]
            path = line[3:]
            letter = status.strip() or "?"
            files.append({"status": letter, "path": path})
        return files

    def add(self, paths: list[str]) -> subprocess.CompletedProcess:
        return self.run("add", *paths)

    def unstage(self, paths: list[str]) -> subprocess.CompletedProcess:
        return self.run("reset", "HEAD", "--", *paths)

    def discard(self, paths: list[str]) -> subprocess.CompletedProcess:
        return self.run("checkout", "--", *paths)

    def stash(self, message: str) -> subprocess.CompletedProcess:
        return self.run("stash", "push", "-m", message)

    def commit(self, message: str) -> subprocess.CompletedProcess:
        return self.run("commit", "-m", message)

    def sync(self) -> subprocess.CompletedProcess:
        pull = self.run("pull", "--rebase")
        if pull.returncode != 0:
            return pull
        return self.run("push")

    def branches(self) -> dict:
        proc = self.run("branch", "--list")
        branches = []
        current = None
        for line in proc.stdout.splitlines():
            name = line.strip().lstrip("* ").strip()
            if line.startswith("*"):
                current = name
            branches.append(name)
        return {"branches": branches, "current": current}

    def checkout(self, branch: str) -> subprocess.CompletedProcess:
        return self.run("checkout", branch)

    def log(self, limit: int = 20) -> list[dict]:
        proc = self.run(
            "log",
            f"-{limit}",
            "--pretty=format:%H|%an|%ae|%s|%ci",
        )
        commits = []
        for line in proc.stdout.splitlines():
            parts = line.split("|", 4)
            if len(parts) < 5:
                continue
            commits.append(
                {
                    "hash": parts[0],
                    "author": parts[1],
                    "email": parts[2],
                    "message": parts[3],
                    "date": parts[4],
                }
            )
        return commits

    def exec_allowed(self, command: list[str]) -> subprocess.CompletedProcess:
        allowed = {
            "status", "log", "diff", "show", "branch", "remote", "fetch",
            "pull", "push", "add", "reset", "checkout", "commit", "stash",
            "merge", "rebase", "tag", "blame",
        }
        if not command or command[0] not in allowed:
            raise ValueError(f"Git subcommand not allowed: {command[:1]}")
        return self.run(*command)


# Module-level override for tests
_override_runner: Callable | None = None


def set_runner_override(runner: Callable | None):
    global _override_runner
    _override_runner = runner


def get_git_runner(cwd: str) -> GitRunner:
    return GitRunner(cwd, runner=_override_runner)
