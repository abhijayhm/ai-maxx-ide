# Operations

Day-to-day commands for server, tunnel, Flutter app, and Docker Android emulator.

## Environment (`.env`)

```
SERVER_DOMAIN=aimaxx.example.com
API_KEY=…
BIND_PORT=8000
```

Flutter defaults are in `app/lib/core/config/app_config.dart` (same hostname).

## Server + tunnel

```powershell
# Terminal 1 — ASGI
cd C:\all-files\misc\ai-maxx-ide\server
uvicorn config.asgi:application --host 127.0.0.1 --port 8000

# Terminal 2 — tunnel
cloudflared tunnel run ai-maxx-ide
```

Public URL: `https://aimaxx.example.com`

WebSocket sync: `wss://aimaxx.example.com/ws/sync/{workspace_id}/`

## Flutter app

```powershell
cd C:\all-files\misc\ai-maxx-ide\app
flutter pub get
flutter run                    # USB device
flutter run -d emulator-5554   # Docker emulator
```

## Docker Android emulator (Windows, no KVM)

Location: `docker/android-emulator/`

```powershell
# Start (first boot ~10–20 min without KVM)
.\scripts\dev\emulator_setup.ps1

# Screen in browser (headful QEMU + noVNC)
.\scripts\dev\emulator_screen.ps1
# → http://localhost:6080/vnc.html?autoconnect=true&resize=scale

# ADB
adb connect localhost:5555

# Stop
.\scripts\dev\emulator_stop.ps1
```

Full stack script: `scripts/dev/run_dev_stack.ps1`

## Verify sync

1. Open app → Menu → Authenticate (API key from `.env`)
2. Pick exposed root → Open workspace
3. Header should show **AI Maxx IDE** + `Indexing workspace…` then `Synced`
4. Network inspector should show **WebSocket** to `/ws/sync/1/`, not pending `POST …/sync/`

## Tests

```powershell
cd server
pytest tests/test_sync_ws.py tests/test_files.py tests/test_devices_workspaces.py -q
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| 404 on wrong hostname | Use `aimaxx.example.com`, not `aimaxxssh…` |
| WS fails, REST works | Run `uvicorn`, not `runserver` |
| Workspace spinner stuck | Fixed: session refresh deadlock — ensure latest `app_providers.dart` |
| Sync timeout | Large workspace: wait for batched `files` frames; check server logs |
| Emulator offline | `adb connect localhost:5555`; rebuild image if entrypoint changed |

More commands: `docs/commands.txt`
