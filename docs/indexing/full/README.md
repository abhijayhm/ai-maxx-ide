# AI Maxx IDE — Full System Reference

This folder documents how the mobile workbench, Django server, workspace indexing, and dev stack work end-to-end.

| Document | Contents |
|----------|----------|
| [dart-structure.md](./dart-structure.md) | Flutter app layout, every Dart file, providers, routing |
| [sync-flow.md](./sync-flow.md) | Workspace indexing over WebSocket (not HTTP) |
| [server.md](./server.md) | Django API, WebSocket consumers, sync service |
| [operations.md](./operations.md) | Dev server, Cloudflare tunnel, Android emulator |

## Architecture (one screen)

```
┌─────────────────────┐         wss://aimaxx.example.com
│  Flutter app        │◄──────────────────────────────────────────────┐
│  (Android/iOS)      │         https://.../api/ (REST: auth, files)   │
│                     │         wss://.../ws/sync/{id}/ (indexing)     │
│  SQLite file index  │         wss://.../ws/terminals/, /ws/agent/    │
└─────────────────────┘                                                │
                                                                       ▼
                                                        ┌──────────────────────────┐
                                                        │  Windows workstation      │
                                                        │  Django ASGI (uvicorn)    │
                                                        │  Cloudflare tunnel :8000  │
                                                        │  Exposed workspace dirs   │
                                                        │  Cursor SDK agent bridge  │
                                                        └──────────────────────────┘
```

## What changed (sync optimization)

**Before:** Opening a workspace fired two blocking HTTP POSTs:

- `POST /api/workspaces/{id}/bind-cursor/` — 2s+
- `POST /api/workspaces/{id}/sync/` — single huge JSON body (could be 100MB+), request stayed `httpPending`

**After:** One WebSocket session handles everything:

1. Client connects to `wss://{host}/ws/sync/{workspace_id}/?api_key=…&device_hash=…&workspace_id=…`
2. Client sends `{"type":"start"}`
3. Server runs **bind-cursor in parallel** (non-blocking for the client)
4. Server sends **metadata tree** (no embedded file bodies)
5. Server **pushes file batches** (32 paths per frame) with progress counters
6. Server sends `{"type":"complete"}`

The Flutter `workspaceSyncProvider.start()` returns immediately; sync runs in the background and updates the header status label.

REST sync endpoints (`POST .../sync/`, `POST .../sync/files/`) remain for tests and backward compatibility but the app no longer uses them.

## UI

- **Shell header** shows **AI Maxx IDE** (not a search field).
- **Projects tab** keeps the file search field (searches the local SQLite index).

## Quick start

```powershell
# Server (ASGI — required for WebSockets)
cd server
uvicorn config.asgi:application --host 127.0.0.1 --port 8000

# Tunnel (separate terminal)
cloudflared tunnel run ai-maxx-ide

# Flutter app
cd app
flutter run
```

See [operations.md](./operations.md) for emulator Docker setup and scripts.
