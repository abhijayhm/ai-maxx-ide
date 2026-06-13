# Backend definition

Django ASGI server for the mobile IDE agent workstation. Implements REST + WebSocket surfaces inferred from [wireframes_v4.html](../wireframes/wireframes_v4.html), Cursor agent streaming via [cursor-sdk.md](../third-party-docs/cursor-sdk.md), and Windows desktop remote control.

## Stack

| Layer | Choice | Notes |
| --- | --- | --- |
| Framework | Django 5.x | ORM, admin, settings |
| API | Django REST Framework | JSON endpoints |
| Realtime | Django Channels 4.x | `AsyncWebsocketConsumer` only |
| ASGI server | Uvicorn | Production; `runserver` for dev |
| Agent | `cursor-sdk` | Local runtime against workspace `cwd` |
| Screen | `aiortc` + `mss` + `av` (PyAV) | Custom `VideoStreamTrack` |
| Input | `pynput` | Mouse + keyboard combo executor |
| Terminal | `asyncssh` or `paramiko` + `winpty` / `pywinpty` | SSH sessions; local ConPTY on Windows |
| Git | `subprocess` → `git` CLI | No Dulwich; match user’s installed git |
| Search (server) | `ripgrep` subprocess preferred, `grep` fallback | Workspace-scoped |

## Django apps

| App | Responsibility |
| --- | --- |
| `core` | Models, middleware, auth, path sandbox |
| `agents` | Cursor SDK bridge, agent messages, WS stream |
| `files` | Directory listing, sync tree, file bytes |
| `gitapp` | Porcelain git operations for Git tab |
| `terminals` | PTY + SSH session management |
| `remote` | WebRTC signaling + input event pipeline |

## Data models

### `DeviceIdentifier`

```python
class DeviceIdentifier(models.Model):
    hash = models.CharField(max_length=64, unique=True, db_index=True)
    data = models.JSONField()  # raw payload from Flutter device_info
    label = models.CharField(max_length=128, blank=True)  # admin-friendly name
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    last_seen_at = models.DateTimeField(auto_now=True)
```

Registration flow:

1. Flutter posts `data` from `getSystemHashIdentifier()` source fields.
2. Server computes/verifies hash, upserts row, sets `last_seen_at`.
3. Middleware rejects unknown or inactive hashes.

### `Workspace`

```python
class Workspace(models.Model):
    absolute_path = models.TextField()
    device = models.ForeignKey(DeviceIdentifier, on_delete=models.CASCADE, related_name="workspaces")
    label = models.CharField(max_length=255, blank=True)  # defaults to folder basename
    cursor_agent_id = models.CharField(max_length=128, blank=True)  # local agent-*
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return Path(self.absolute_path).name or self.absolute_path
```

Rules:

- `absolute_path` must be a subpath of one `EXPOSED_DIRECTORIES_ABSOLUTE_PATHS` entry (normalized, case-aware on Windows).
- One device may have many workspaces; client picks active via header or query.

### `AgentMessage`

```python
class Sender(models.TextChoices):
    USER = "user"
    SYSTEM = "system"

class AgentMessage(models.Model):
    timestamp = models.DateTimeField(auto_now_add=True)
    sender = models.CharField(max_length=16, choices=Sender.choices)
    receiver = models.CharField(max_length=16, choices=Sender.choices)
    device = models.ForeignKey(DeviceIdentifier, on_delete=models.CASCADE)
    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE)
    run_id = models.CharField(max_length=64, blank=True)
    payload = models.JSONField()  # text, tool_call, status, file_edit, etc.
```

Persist streamed events for history reload; live stream still goes over WebSocket.

## Authentication & middleware

### Headers (all protected routes)

```
X-API-Key: <API_KEY>
X-Device-Identifier: <sha256 hash>
X-Workspace-Id: <optional uuid/int, required for workspace-scoped routes>
```

### `core.middleware.DeviceAuthMiddleware`

Order: after CORS, before views.

1. Skip `/api/health/`, `/api/devices/register/`.
2. Compare `X-API-Key` to `settings.API_KEY` → `403` on mismatch.
3. Load `DeviceIdentifier` by hash → `403` if missing/inactive.
4. Attach `request.device` to Django request; for DRF, also `request.auth_device`.

### DRF authentication class

`DeviceAPIKeyAuthentication` — same checks for REST; returns `(device, None)` principal.

### WebSocket middleware

`AuthMiddlewareStack` + custom `DeviceAuthWsMiddleware` parsing query string or first JSON auth frame:

```json
{ "type": "auth", "api_key": "...", "device_hash": "...", "workspace_id": 12 }
```

Failure → close with code `4401`.

## Path sandbox

```python
def resolve_allowed_path(requested: str) -> Path:
    """Raise PermissionDenied if not under EXPOSED_DIRECTORIES_ABSOLUTE_PATHS."""
```

- Normalize with `Path.resolve()` on Windows.
- Directory listings never follow symlinks outside roots.
- File download rejects `..`, device paths, and non-file nodes.

## REST API

Base path: `/api/`. All responses JSON unless file download.

### Health & device

| Method | Path | Body | Response |
| --- | --- | --- | --- |
| GET | `/health/` | — | `{ "ok": true }` |
| POST | `/devices/register/` | `{ "hash", "data" }` | `{ "id", "hash", "registered": true }` |
| POST | `/devices/identifier/` | `{ "data" }` | `{ "hash" }` — server-side hash if client wants verification |

`POST /devices/register/` requires API key only (no pre-existing device).

### Workspaces

| Method | Path | Description |
| --- | --- | --- |
| GET | `/workspaces/` | List workspaces for device |
| POST | `/workspaces/` | Create/open workspace `{ "absolute_path" }` |
| GET | `/workspaces/{id}/` | Detail |
| PATCH | `/workspaces/{id}/` | Rename label, set active |
| DELETE | `/workspaces/{id}/` | Soft-delete (`is_active=false`) |
| POST | `/workspaces/{id}/bind-cursor/` | Create/resume Cursor local agent for `cwd` |

**`POST /workspaces/` side effects:**

1. Validate path under exposed roots.
2. Upsert `Workspace` row.
3. Call `cursor_sdk.AsyncClient.launch_bridge` + `agents.create(model=..., local=LocalAgentOptions(cwd=path))`.
4. Store `cursor_agent_id` on workspace.

### Files & directories

| Method | Path | Description |
| --- | --- | --- |
| GET | `/files/roots/` | Default listing of exposed roots: `[{ "full_path", "folder_name" }]` |
| GET | `/files/by-path/` | Query `path` — children dirs + files, or file bytes |
| GET | `/files/download/` | Query `path` — streaming file body with `Content-Type` |
| POST | `/files/mkdir/` | `{ "path", "name" }` |
| POST | `/files/touch/` | `{ "path", "name" }` create empty file |
| POST | `/workspaces/{id}/sync/` | Full workspace tree snapshot |

#### `GET /files/by-path/`

| Query | Behavior |
| --- | --- |
| omitted / empty | Same as `/files/roots/` |
| directory | `{ "type": "directory", "path", "children": [{ "name", "path", "type", "size", "modified_at" }] }` |
| file | `{ "type": "file", "path", "size", "content_base64" }` or raw download via `/download/` |

#### `POST /workspaces/{id}/sync/`

Response tree node:

```json
{
  "path": "C:/dev/project",
  "name": "project",
  "type": "directory",
  "children": [],
  "size": 0,
  "sync_policy": "metadata_only | inline",
  "modified_at": "ISO8601"
}
```

Files `> 1_048_576` bytes: `sync_policy: "metadata_only"`.

### Search

| Method | Path | Body / query |
| --- | --- | --- |
| GET | `/search/files/` | `q`, `workspace_id`, `limit` — fuzzy filename search under workspace |
| POST | `/search/grep/` | `{ "pattern", "glob", "workspace_id", "case_sensitive" }` |

Grep response row (matches wireframe result list):

```json
{
  "path": "utils/parser.cpp",
  "line_start": 1,
  "line_end": 42,
  "matches": [{ "line": 10, "text": "..." }]
}
```

### Agent (HTTP helpers)

| Method | Path | Description |
| --- | --- | --- |
| GET | `/agent/messages/` | Paginated `AgentMessage` for workspace |
| POST | `/agent/stop/` | Cancel active Cursor run |
| GET | `/agent/status/` | `{ "running", "run_id" }` |

Primary agent I/O is WebSocket (below).

### Git (Screen 5)

All routes scoped to `workspace_id`; execute git in `workspace.absolute_path`.

| Method | Path | Body | Action |
| --- | --- | --- | --- |
| GET | `/git/status/` | — | Changed files with letter `M/A/D`, paths |
| POST | `/git/stage/` | `{ "paths": [] }` | `git add` |
| POST | `/git/unstage/` | `{ "paths": [] }` | reset |
| POST | `/git/discard/` | `{ "paths": [] }` | checkout -- paths |
| POST | `/git/stash/` | `{ "message" }` | stash push |
| POST | `/git/commit/` | `{ "message" }` | commit |
| POST | `/git/sync/` | — | pull --rebase + push (configurable) |
| POST | `/git/exec/` | `{ "command" }` | raw git argv list; safety allowlist |
| GET | `/git/branches/` | — | branch list, current |
| POST | `/git/checkout/` | `{ "branch" }` | branch switch (Select button) |
| GET | `/git/log/` | `limit` | commit history graph rows |

### Terminals (HTTP metadata)

| Method | Path | Description |
| --- | --- | --- |
| GET | `/terminals/` | List sessions |
| POST | `/terminals/` | Create `{ "type": "local|ssh", "name", "ssh_host?", "ssh_user?" }` |
| DELETE | `/terminals/{id}/` | Kill session |

PTY I/O is WebSocket.

## WebSocket endpoints

Routing prefix: `/ws/`. Subprotocol: JSON text frames.

### `/ws/agent/`

**Consumer:** `agents.consumers.AgentConsumer`

| Client → server | Payload |
| --- | --- |
| `auth` | API key + device + workspace (if not in middleware) |
| `message` | `{ "text", "mode?", "attachments?", "references?" }` |
| `stop` | cancel active run |

| Server → client | Payload |
| --- | --- |
| `run_started` | `{ "run_id" }` |
| `stream` | Cursor `SDKMessage` serialized (assistant, thinking, tool_call, status) |
| `run_finished` | `{ "status", "result", "duration_ms" }` |
| `error` | `{ "code", "message" }` |

Implementation sketch:

```python
async with await AsyncClient.launch_bridge(workspace=cwd) as client:
    agent = await client.agents.resume(workspace.cursor_agent_id)  # or create
    run = await agent.send(text)
    async for message in run.messages():
        await self.send_json({"type": "stream", "message": dataclasses.asdict(message)})
    result = await run.wait()
```

Use `async for` with short `asyncio.sleep(0)` yields if event loop starvation appears on Windows.

### `/ws/terminals/{session_id}/`

**Consumer:** `terminals.consumers.TerminalConsumer`

| Direction | Event |
| --- | --- |
| Client → | `input` (bytes base64), `resize` `{cols, rows}` |
| Server → | `output` (bytes base64), `exit` `{code}` |

**SSH behavior (wireframe):**

- On `type: "ssh"` session create, connect with stored credentials or key.
- After connect, run `cd <workspace.absolute_path>` automatically.
- Expose + / trash via REST delete.

### `/ws/remote/`

Two channels in one consumer (or split):

#### Signaling (WebRTC)

| Client → | `offer`, `answer`, `ice_candidate` |
| Server → | `answer`, `ice_candidate`, `connected` |

Server starts on boot:

```python
class ScreenTrack(VideoStreamTrack):
    """mss capture thread → queue(maxsize=1) → recv() → VideoFrame"""
```

- Capture primary monitor (`mss.monitors[1]`).
- Crop/scale to multiple-of-8 dimensions before `VideoFrame.from_ndarray`.
- `MediaRelay` if multiple viewers (usually one mobile client).

#### Input channel

| Client → | `input_batch` |

```json
{
  "type": "input_batch",
  "events": [
    { "op": "pointer_move", "x": 0.42, "y": 0.18, "normalized": true },
    { "op": "click", "button": "left" },
    { "op": "key_combo", "keys": ["ctrl", "shift", "esc"] }
  ],
  "dispatch": true
}
```

**Staging semantics (wireframe Remote tab):**

| `dispatch` | Meaning |
| --- | --- |
| `false` | Append to server-side staging buffer (Keyboard tab `+`) |
| n/a + empty batch with `clear` | Discard staging (`x`) |
| `true` | Execute staging + batch as injected input (`✓`) |

Executor (`input_executor.py`):

```python
from pynput.keyboard import Controller as KbdController, Key
from pynput.mouse import Controller as MouseController, Button

def execute_combo(keys: list[str]): ...
def execute_pointer(...): ...
```

Map normalized coordinates to absolute screen pixels. Rate-limit batches to ~60/s.

**Security:** Remote WS only if `request.device` authorized; optional `REMOTE_INPUT_ENABLED=true` env kill switch.

## Cursor SDK integration details

| Setting | Value |
| --- | --- |
| Runtime | `local` only (workspace on same Windows host) |
| Model | `composer-2.5` default; overridable per message |
| `setting_sources` | `["project", "user"]` so `.cursor/mcp.json` loads |
| Bridge | `AsyncClient.launch_bridge(workspace=cwd)` per workspace |

On workspace open:

```python
agent = await client.agents.create(
    model="composer-2.5",
    api_key=settings.CURSOR_API_KEY,
    local=LocalAgentOptions(cwd=workspace_path, setting_sources=["project", "user"]),
)
workspace.cursor_agent_id = agent.agent_id
```

Reference: [cursor-sdk.md](../third-party-docs/cursor-sdk.md) — `Agent.resume`, `run.messages()`, `run.cancel()`.

## Error codes

| HTTP | Code | When |
| --- | --- | --- |
| 403 | `invalid_api_key` | Wrong `X-API-Key` |
| 403 | `device_not_registered` | Unknown hash |
| 403 | `path_not_allowed` | Outside exposed directories |
| 404 | `workspace_not_found` | |
| 409 | `agent_busy` | Cursor run in progress |
| 503 | `cursor_unavailable` | Bridge failed to start |

## Admin

Use Django admin for `DeviceIdentifier` approval, `Workspace` inspection, and `AgentMessage` audit.

## Testing strategy

| Area | Approach |
| --- | --- |
| Path sandbox | Unit tests with temp dirs |
| Auth middleware | DRF APIClient + WS communicator |
| Git | Mock subprocess |
| Agent | Integration test marked `@pytest.mark.cursor` (optional) |
| Remote | Headless screen track smoke test |

## Non-goals (v1)

- Multi-user RBAC beyond device + API key
- Cloud Cursor agents (local workstation only)
- FTP protocol (wireframe “FTP Navigator” is a **remote filesystem tree** over sandboxed paths, not FTP wire protocol)
- Editing files in mobile editor (search + reference + agent apply only)
