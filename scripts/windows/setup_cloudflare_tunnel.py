#!/usr/bin/env python3
import os
import sys
import json
import shutil
import socket
import platform
import subprocess
from pathlib import Path

APP_NAME = "cf-python-ssh"
WINDOWS_CF_DIR = Path(r"C:\cloudflared")
WINDOWS_CF_EXE = WINDOWS_CF_DIR / "cloudflared.exe"


def run(cmd, shell=False, check=False, capture=False):
    print(f"\n>>> {cmd if isinstance(cmd, str) else ' '.join(cmd)}")
    return subprocess.run(
        cmd,
        shell=shell,
        check=check,
        text=True,
        capture_output=capture,
    )


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


def app_py_path():
    return Path.cwd() / "app.py"


def ssh_config_path():
    if is_windows():
        return Path.home() / ".ssh" / "config"
    return Path.home() / ".ssh" / "config"


def port_open_local(port: int, host="127.0.0.1"):
    s = socket.socket()
    s.settimeout(1)
    try:
        s.connect((host, port))
        return True
    except Exception:
        return False
    finally:
        s.close()


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


def ensure_windows_ssh_server():
    ps = r'''
$server = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($server.State -ne 'Installed') {
  Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
}
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
}
Get-Service sshd | Select-Object Status,Name,StartType
'''
    run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps], check=True)


def ensure_ubuntu_ssh_server():
    cmds = [
        "sudo apt-get update",
        "sudo apt-get install -y openssh-server",
        "sudo systemctl enable --now ssh || sudo systemctl enable --now sshd",
        "sudo ufw allow 22/tcp || true",
    ]
    for c in cmds:
        run(c, shell=True, check=True)


def ensure_ssh_server():
    if port_open_local(22):
        print("SSH server already listening on localhost:22")
        return
    if is_windows():
        ensure_windows_ssh_server()
    else:
        ensure_ubuntu_ssh_server()
    if not port_open_local(22):
        print("Warning: SSH port 22 is still not reachable locally. Verify sshd status.")


def write_python_app(port: int):
    if app_py_path().exists():
        print(f"Python app already exists: {app_py_path()}")
        return
    app_code = f'''from flask import Flask\napp = Flask(__name__)\n\n@app.get("/")\ndef home():\n    return {{"ok": True, "service": "{APP_NAME}", "port": {port}}}\n\nif __name__ == "__main__":\n    app.run(host="127.0.0.1", port={port})\n'''
    app_py_path().write_text(app_code, encoding="utf-8")
    print(f"Created {app_py_path()}")


def read_existing_tunnel_id():
    cfg = config_path()
    if not cfg.exists():
        return None
    for line in cfg.read_text(encoding="utf-8").splitlines():
        if line.strip().startswith("tunnel:"):
            return line.split(":", 1)[1].strip()
    return None


def find_credentials_file(tunnel_id: str):
    p = cf_home() / f"{tunnel_id}.json"
    return p if p.exists() else None


def login_if_needed():
    cert = cf_home() / "cert.pem"
    if cert.exists():
        print(f"Cloudflare login already present: {cert}")
        return
    print("Cloudflare login required. A browser window should open.")
    run(["cloudflared", "tunnel", "login"], check=True)


def create_tunnel_if_needed(tunnel_name: str):
    tunnel_id = read_existing_tunnel_id()
    if tunnel_id and find_credentials_file(tunnel_id):
        print(f"Existing tunnel detected: {tunnel_id}")
        return tunnel_id

    result = run(["cloudflared", "tunnel", "create", tunnel_name], capture=True)
    if result.returncode != 0:
        raise SystemExit(result.stderr or result.stdout or "Failed to create tunnel")

    text = (result.stdout or "") + "\n" + (result.stderr or "")
    tunnel_id = None
    for token in text.replace("\n", " ").split():
        if token.count("-") == 4 and len(token) >= 36:
            tunnel_id = token.strip()
            break
    if not tunnel_id:
        raise SystemExit("Tunnel created but tunnel ID could not be parsed. Inspect output manually.")
    return tunnel_id


def write_config(tunnel_id: str, app_hostname: str, ssh_hostname: str, app_port: int):
    ensure_dir(cf_home())
    cred = find_credentials_file(tunnel_id)
    if not cred:
        raise SystemExit(f"Credentials file not found for tunnel ID {tunnel_id}")

    content = f'''tunnel: {tunnel_id}
credentials-file: {cred}

ingress:
  - hostname: {app_hostname}
    service: http://127.0.0.1:{app_port}
  - hostname: {ssh_hostname}
    service: ssh://localhost:22
  - service: http_status:404
'''
    config_path().write_text(content, encoding="utf-8")
    print(f"Wrote config: {config_path()}")


def ensure_dns_route(tunnel_name: str, hostname: str):
    result = run(["cloudflared", "tunnel", "route", "dns", tunnel_name, hostname], capture=True)
    text = ((result.stdout or "") + "\n" + (result.stderr or "")).lower()
    if result.returncode == 0 or "already exists" in text:
        print(f"DNS route ready for {hostname}")
        return
    print(result.stdout)
    print(result.stderr)
    raise SystemExit(f"Failed to route DNS for {hostname}")


def install_service_windows_if_requested():
    if not is_windows():
        return
    answer = input("Install cloudflared as Windows service now? [y/N]: ").strip().lower()
    if answer != "y":
        return
    result = run(["cloudflared", "service", "install"], capture=True)
    print(result.stdout)
    print(result.stderr)


def write_ssh_client_config(ssh_hostname: str, username: str):
    p = ssh_config_path()
    ensure_dir(p.parent)
    block = f"""
Host {ssh_hostname}
  HostName {ssh_hostname}
  User {username}
  ProxyCommand cloudflared access ssh --hostname %h
""".strip() + "\n"
    existing = p.read_text(encoding="utf-8") if p.exists() else ""
    if f"Host {ssh_hostname}" in existing:
        print(f"SSH client config already contains host {ssh_hostname}")
        return
    with p.open("a", encoding="utf-8") as f:
        if existing and not existing.endswith("\n"):
            f.write("\n")
        f.write("\n" + block)
    print(f"Updated SSH client config: {p}")


def main():
    print("Cloudflare Tunnel + Python + SSH setup")
    print("This script is rerun-safe for config/app generation and most setup steps.")

    ensure_cloudflared()

    domain = input("Base domain on Cloudflare (example.com): ").strip()
    app_sub = input("App subdomain [app]: ").strip() or "app"
    ssh_sub = input("SSH subdomain [ssh]: ").strip() or "ssh"
    tunnel_name = input(f"Tunnel name [{APP_NAME}]: ").strip() or APP_NAME
    app_port_raw = input("Local Python app port [5000]: ").strip() or "5000"
    ssh_user = input("SSH username for client config: ").strip()

    try:
        app_port = int(app_port_raw)
    except ValueError:
        raise SystemExit("Port must be an integer")

    app_hostname = f"{app_sub}.{domain}"
    ssh_hostname = f"{ssh_sub}.{domain}"

    if is_windows():
        ensure_windows_ssh_server()
    else:
        answer = input("Install/ensure OpenSSH server on Ubuntu/Debian host? [y/N]: ").strip().lower()
        if answer == "y":
            ensure_ubuntu_ssh_server()
        elif not port_open_local(22):
            print("SSH is not listening on localhost:22. Install/configure openssh-server before using SSH tunnel.")

    login_if_needed()
    tunnel_id = create_tunnel_if_needed(tunnel_name)
    write_config(tunnel_id, app_hostname, ssh_hostname, app_port)
    ensure_dns_route(tunnel_name, app_hostname)
    ensure_dns_route(tunnel_name, ssh_hostname)
    write_python_app(app_port)

    if ssh_user:
        write_ssh_client_config(ssh_hostname, ssh_user)

    install_service_windows_if_requested()

    print("\nDone.")
    print(f"App hostname: https://{app_hostname}")
    print(f"SSH hostname: {ssh_hostname}")
    print(f"Config file: {config_path()}")
    print("\nNext steps:")
    print(f"1) pip install flask")
    print(f"2) python {app_py_path().name}")
    print(f"3) cloudflared tunnel run {tunnel_name}")
    print(f"4) SSH client command: ssh {ssh_hostname}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("\nCancelled by user.")
