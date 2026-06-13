# Server Reference

Django ASGI backend at `server/`. Serves REST under `/api/` and WebSockets under `/ws/`.

## Run modes

```powershell
# REST only (no WebSockets) — smoke tests only
python manage.py runserver 8000

# Production / tunnel — REST + WebSockets
uvicorn config.asgi:application --host 127.0.0.1 --port 8000
```

Cloudflare tunnel (`cloudflared tunnel run ai-maxx-ide`) maps `aimaxx.organisationapp.online` → `127.0.0.1:8000`.

## WebSocket routes (`config/routing.py`)

| Path | Consumer | Purpose |
|------|----------|---------|
| `/ws/agent/` | `AgentConsumer` | Cursor agent streaming |
| `/ws/sync/<id>/` | `WorkspaceSyncConsumer` | Workspace indexing |
| `/ws/terminals/<id>/` | `TerminalConsumer` | PTY I/O |
| `/ws/remote/` | `RemoteConsumer` | WebRTC signaling |

Auth: query `api_key`, `device_hash`, optional `workspace_id` (`core/ws_auth.py`).

## Workspace REST (still used by app)

| Method | Path | Use |
|--------|------|-----|
| POST | `/api/devices/register/` | Register device hash |
| GET | `/api/workspaces/` | List workspaces |
| POST | `/api/workspaces/` | Open workspace by path |
| PATCH | `/api/workspaces/{id}/` | Set active workspace |
| GET | `/api/files/roots/` | Browse exposed roots (menu) |

Legacy sync REST (tests / tools):

| Method | Path |
|--------|------|
| POST | `/api/workspaces/{id}/sync/` |
| POST | `/api/workspaces/{id}/sync/files/` |
| POST | `/api/workspaces/{id}/bind-cursor/` |

## Sync service (`files/sync_service.py`)

```python
build_workspace_sync_tree(workspace)  # metadata tree + sync_summary
collect_inline_paths(node)            # paths with sync_policy == inline
fetch_sync_file_batch(root, paths)    # read + base64 encode batch
```

## Key settings (`config/settings.py`)

| Variable | Purpose |
|----------|---------|
| `API_KEY` | Device auth |
| `EXPOSED_DIRECTORIES_ABSOLUTE_PATHS` | Roots the app can open |
| `CURSOR_API_KEY` | Cursor SDK agent |
| `FILE_SYNC_INLINE_MAX_BYTES` | Inline sync size cap |
| `SYNC_FILES_BATCH_MAX_PATHS` | WS batch size |

## Request headers (REST)

```
X-API-Key: …
X-Device-Identifier: {sha256 device hash}
X-Workspace-Id: {active workspace id}
```
