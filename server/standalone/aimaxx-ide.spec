# -*- mode: python ; coding: utf-8 -*-
"""Build ai-maxx-ide standalone server (Windows onedir).

Usage (from server/, venv active):
  ..\env\Scripts\pip install -r requirements.txt -r requirements-packaging.txt
  ..\env\Scripts\pyinstaller standalone\aimaxx-ide.spec --noconfirm

Output: server\standalone\dist\aimaxx-ide\aimaxx-ide.exe
Place .env beside aimaxx-ide.exe before first run.
"""

from pathlib import Path

from PyInstaller.utils.hooks import collect_all, collect_submodules

block_cipher = None

spec_dir = Path(SPECPATH)
server_dir = spec_dir.parent
repo_root = server_dir.parent

entry_script = str(spec_dir / "entrypoint.py")

datas = [
    (str(repo_root / "scripts" / "windows"), str(Path("scripts") / "windows")),
    (str(repo_root / "sample.env"), "."),
    (str(server_dir / "dashboard" / "templates"), str(Path("dashboard") / "templates")),
]

binaries: list = []
hiddenimports: list = [
    "standalone.bootstrap",
    "standalone.entrypoint",
    "standalone.run_script",
    "standalone.asgi_server",
    "config.settings",
    "config.asgi",
    "config.routing",
    "config.urls",
    "core.urls",
    "dashboard.urls",
    "dashboard.api_urls",
    "dashboard.views",
    "dashboard.apps",
    "agents.consumers",
    "agents.urls",
    "agents.bridge_launcher",
    "files.urls",
    "ide.consumers",
    "ide.views",
    "terminals.consumers",
    "terminals.urls",
    "remote.consumers",
    "terminals.pty_manager",
    "terminals.output_format",
    "uvicorn.lifespan.on",
    "uvicorn.lifespan.off",
    "uvicorn.protocols.http.auto",
    "uvicorn.protocols.http.h11_impl",
    "uvicorn.protocols.http.httptools_impl",
    "uvicorn.protocols.websockets.auto",
    "uvicorn.protocols.websockets.wsproto_impl",
    "uvicorn.protocols.websockets.websockets_impl",
    "uvicorn.loops.auto",
    "uvicorn.loops.asyncio",
]

for package in (
    "django",
    "rest_framework",
    "channels",
    "daphne",
    "uvicorn",
    "environ",
    "watchdog",
    "ahocorasick",
    "aiortc",
    "av",
    "mss",
    "numpy",
    "pynput",
    "winpty",
    "twisted",
    "autobahn",
    "OpenSSL",
    "whitenoise",
    "cursor_sdk",
):
    try:
        pkg_datas, pkg_binaries, pkg_hidden = collect_all(package)
        datas += pkg_datas
        binaries += pkg_binaries
        hiddenimports += pkg_hidden
    except Exception:
        pass

hiddenimports += collect_submodules("django.contrib")
hiddenimports += collect_submodules("channels")
hiddenimports += collect_submodules("daphne")
hiddenimports += collect_submodules("rest_framework")
for app_pkg in (
    "config",
    "core",
    "dashboard",
    "ide",
    "agents",
    "files",
    "terminals",
    "remote",
    "standalone",
):
    hiddenimports += collect_submodules(app_pkg)

a = Analysis(
    [entry_script],
    pathex=[str(server_dir)],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="aimaxx-ide",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="aimaxx-ide",
)
