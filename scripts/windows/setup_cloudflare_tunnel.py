#!/usr/bin/env python3
"""Cloudflare Tunnel bootstrap — SERVER_DOMAIN only (Django API + WSS on :8000)."""
import json
import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path

APP_NAME = "ai-maxx-ide"
TUNNEL_ID_RE = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
    re.IGNORECASE,
)
WINDOWS_CF_DIR = Path(r"C:\cloudflared")
WINDOWS_CF_EXE = WINDOWS_CF_DIR / "cloudflared.exe"
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent


def is_admin() -> bool:
    if not is_windows():
        return os.geteuid() == 0
    import ctypes

    return bool(ctypes.windll.shell32.IsUserAnAdmin())


def run(cmd, shell=False, check=False, capture=False):
    print(f"\n>>> {cmd if isinstance(cmd, str) else ' '.join(cmd)}")
    result = subprocess.run(
        cmd,
        shell=shell,
        check=check,
        text=True,
        capture_output=capture,
    )
    if capture:
        if result.stdout:
            print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")
        if result.stderr:
            print(result.stderr, end="" if result.stderr.endswith("\n") else "\n")
    return result


def is_windows():
    return platform.system().lower().startswith("win")


def which(name):
    return shutil.which(name)


def ensure_dir(p: Path):
    p.mkdir(parents=True, exist_ok=True)


def cf_home():
    return Path.home() / ".cloudflared"


def config_path():
    return cf_home() / "config.yml"


def env_file_path():
    return REPO_ROOT / ".env"


def sample_env_path():
    return REPO_ROOT / "sample.env"


def parse_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def load_env() -> dict[str, str]:
    path = env_file_path()
    if not path.exists():
        sample = sample_env_path()
        raise SystemExit(
            f"Missing {path}\n"
            f"Copy {sample} to .env and set SERVER_DOMAIN, TUNNEL_NAME, SERVER_PORT."
        )
    return parse_env_file(path)


def env_bool(env: dict[str, str], key: str, default: bool = False) -> bool:
    raw = env.get(key, str(default)).strip().lower()
    return raw in {"1", "true", "yes", "y", "on"}


def env_int(env: dict[str, str], key: str, default: int | None = None) -> int:
    raw = env.get(key, "").strip()
    if not raw and default is not None:
        return default
    try:
        return int(raw)
    except ValueError as exc:
        raise SystemExit(f".env: {key} must be a valid integer") from exc


def require_env(env: dict[str, str], key: str) -> str:
    value = env.get(key, "").strip()
    if not value:
        raise SystemExit(f".env: missing required value {key}")
    return value


def server_port(env: dict[str, str]) -> int:
    if env.get("SERVER_PORT", "").strip():
        return env_int(env, "SERVER_PORT")
    if env.get("BIND_PORT", "").strip():
        return env_int(env, "BIND_PORT")
    if env.get("LOCAL_SERVER_PORT", "").strip():
        return env_int(env, "LOCAL_SERVER_PORT")
    return 9000


def parse_extra_ingress(env: dict[str, str]) -> list[tuple[str, str]]:
    raw = env.get("TUNNEL_EXTRA_INGRESS", "[]").strip() or "[]"
    try:
        items = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(".env: TUNNEL_EXTRA_INGRESS must be valid JSON") from exc
    if not isinstance(items, list):
        raise SystemExit(".env: TUNNEL_EXTRA_INGRESS must be a JSON array")

    rules: list[tuple[str, str]] = []
    for index, item in enumerate(items):
        if not isinstance(item, dict):
            raise SystemExit(f".env: TUNNEL_EXTRA_INGRESS[{index}] must be an object")
        hostname = str(item.get("hostname", "")).strip()
        service = str(item.get("service", "")).strip()
        if not hostname or not service:
            raise SystemExit(
                f".env: TUNNEL_EXTRA_INGRESS[{index}] needs hostname and service"
            )
        rules.append((hostname, service))
    return rules


def build_ingress_rules(env: dict[str, str]) -> list[tuple[str, str]]:
    server_domain = require_env(env, "SERVER_DOMAIN")
    port = server_port(env)

    rules = [(server_domain, f"http://127.0.0.1:{port}")]
    rules.extend(parse_extra_ingress(env))

    seen: set[str] = set()
    for hostname, _ in rules:
        if hostname in seen:
            raise SystemExit(f".env: duplicate tunnel hostname {hostname}")
        seen.add(hostname)
    return rules


def append_path_windows(target_dir: str):
    current = os.environ.get("PATH", "")
    if target_dir.lower() in current.lower():
        return
    os.environ["PATH"] = current + (";" if current else "") + target_dir


def download_cloudflared_windows():
    ensure_dir(WINDOWS_CF_DIR)
    if WINDOWS_CF_EXE.exists():
        print(f"cloudflared already exists at {WINDOWS_CF_EXE}")
        append_path_windows(str(WINDOWS_CF_DIR))
        return
    ps = rf'''
$dir = "{WINDOWS_CF_DIR}"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Invoke-WebRequest -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile "$dir\cloudflared.exe"
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($machinePath -notlike "*C:\cloudflared*") {{
  [Environment]::SetEnvironmentVariable("Path", "$machinePath;C:\cloudflared", "Machine")
}}
'''
    run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps], check=True)
    append_path_windows(str(WINDOWS_CF_DIR))


def ensure_cloudflared():
    exe = which("cloudflared")
    if exe:
        print(f"cloudflared found: {exe}")
        return exe
    if is_windows():
        download_cloudflared_windows()
        exe = which("cloudflared") or str(WINDOWS_CF_EXE)
        print(f"cloudflared ready: {exe}")
        return exe
    raise SystemExit("cloudflared not found. Install it first on this OS.")


def extract_tunnel_id(text: str) -> str | None:
    created = re.search(
        rf"with id\s+({TUNNEL_ID_RE.pattern})",
        text,
        re.IGNORECASE,
    )
    if created:
        return created.group(1)
    matches = TUNNEL_ID_RE.findall(text)
    return matches[-1] if matches else None


def read_existing_tunnel_id():
    cfg = config_path()
    if not cfg.exists():
        return None
    for line in cfg.read_text(encoding="utf-8").splitlines():
        if line.strip().startswith("tunnel:"):
            value = line.split(":", 1)[1].strip()
            match = TUNNEL_ID_RE.search(value)
            return match.group(0) if match else value
    return None


def find_credentials_file(tunnel_id: str):
    p = cf_home() / f"{tunnel_id}.json"
    return p if p.exists() else None


def login_if_needed():
    cert = cf_home() / "cert.pem"
    if cert.exists() and cert.stat().st_size > 0:
        print(f"Cloudflare login already present: {cert}")
        return
    print("Cloudflare login required. A browser window should open.")
    run(["cloudflared", "tunnel", "login"], check=True)


def find_tunnel_id_by_name(tunnel_name: str) -> str | None:
    result = run(["cloudflared", "tunnel", "list"], capture=True)
    if result.returncode != 0:
        return None
    for line in (result.stdout or "").splitlines():
        if tunnel_name not in line:
            continue
        for token in line.split():
            match = TUNNEL_ID_RE.fullmatch(token)
            if match:
                return match.group(0)
    return None


def create_tunnel_if_needed(tunnel_name: str):
    tunnel_id = read_existing_tunnel_id()
    if tunnel_id and find_credentials_file(tunnel_id):
        print(f"Existing tunnel detected in config: {tunnel_id}")
        return tunnel_id

    tunnel_id = find_tunnel_id_by_name(tunnel_name)
    if tunnel_id and find_credentials_file(tunnel_id):
        print(f"Existing tunnel detected in Cloudflare: {tunnel_id}")
        return tunnel_id

    result = run(["cloudflared", "tunnel", "create", tunnel_name], capture=True)
    if result.returncode != 0:
        raise SystemExit(result.stderr or result.stdout or "Failed to create tunnel")

    text = (result.stdout or "") + "\n" + (result.stderr or "")
    tunnel_id = extract_tunnel_id(text)
    if not tunnel_id:
        raise SystemExit("Tunnel created but tunnel ID could not be parsed. Inspect output manually.")
    return tunnel_id


def write_config(tunnel_id: str, ingress_rules: list[tuple[str, str]]):
    ensure_dir(cf_home())
    cred = find_credentials_file(tunnel_id)
    if not cred:
        raise SystemExit(f"Credentials file not found for tunnel ID {tunnel_id}")

    lines = [
        f"tunnel: {tunnel_id}",
        f"credentials-file: {cred}",
        "",
        "ingress:",
    ]
    for hostname, service in ingress_rules:
        lines.append(f"  - hostname: {hostname}")
        lines.append(f"    service: {service}")
    lines.append("  - service: http_status:404")

    content = "\n".join(lines) + "\n"
    config_path().write_text(content, encoding="utf-8")
    print(f"Wrote config: {config_path()}")
    print(f"Ingress hostnames ({len(ingress_rules)}):")
    for hostname, service in ingress_rules:
        print(f"  - {hostname} -> {service}")


def ensure_dns_route(tunnel_name: str, hostname: str):
    result = run(["cloudflared", "tunnel", "route", "dns", tunnel_name, hostname], capture=True)
    text = ((result.stdout or "") + "\n" + (result.stderr or "")).lower()
    if result.returncode == 0 or "already exists" in text or "already configured" in text:
        print(f"DNS route ready for {hostname}")
        return
    print(result.stdout)
    print(result.stderr)
    raise SystemExit(f"Failed to route DNS for {hostname}")


def install_service_windows_if_requested(env: dict[str, str]):
    if not is_windows() or not env_bool(env, "INSTALL_CLOUDFLARED_SERVICE"):
        return
    if not is_admin():
        print(
            "Skipping cloudflared service install (requires Administrator). "
            "Run manually: cloudflared service install"
        )
        return
    result = run(["cloudflared", "service", "install"], capture=True)
    print(result.stdout)
    print(result.stderr)


def main():
    print("Cloudflare Tunnel setup (ai-maxx-ide — server only)")
    print(f"Loading env from: {env_file_path()}")

    env = load_env()
    tunnel_name = require_env(env, "TUNNEL_NAME")
    ingress_rules = build_ingress_rules(env)
    port = server_port(env)
    server_domain = require_env(env, "SERVER_DOMAIN")

    print("This script is rerun-safe for config generation and most setup steps.")
    print(f"Tunnel name: {tunnel_name}")
    print(f"Server API:  https://{server_domain} -> 127.0.0.1:{port}")

    ensure_cloudflared()
    login_if_needed()
    tunnel_id = create_tunnel_if_needed(tunnel_name)
    write_config(tunnel_id, ingress_rules)
    for hostname, _ in ingress_rules:
        ensure_dns_route(tunnel_name, hostname)

    install_service_windows_if_requested(env)

    print("\nDone.")
    print(f"Tunnel:  {tunnel_name}")
    print(f"Config:  {config_path()}")
    print(f"Domains: {len(ingress_rules)} hostname(s) routed")
    for hostname, service in ingress_rules:
        print(f"  - {hostname} ({service})")
    print("\nNext steps:")
    print(f"1) Start Django ASGI on 127.0.0.1:{port}")
    print("   cd server")
    print(f"   uvicorn config.asgi:application --host 127.0.0.1 --port {port}")
    print(f"2) cloudflared tunnel run {tunnel_name}")
    print(f"   Or run scripts\\windows\\start_services.bat")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("\nCancelled by user.")
