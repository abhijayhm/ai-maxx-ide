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
| Terminal | `pywinpty` / `winpty` | Local ConPTY shells on Windows; no external SSH |
| Git | `subprocess` → `git` CLI | No Dulwich; match user’s installed git |
| Search (server) | `ripgrep` subprocess preferred, `grep` fallback | Workspace-scoped |

## Django apps

| App | Responsibility |
| --- | --- |
| `core` | Models, middleware, auth, path sandbox |
| `agents` | Cursor SDK bridge, agent messages, WS stream |
| `files` | Directory listing, sync tree, file bytes |
| `gitapp` | Porcelain git operations for Git tab |
| `terminals` | Local PTY session management + WebSocket I/O |
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

### `Terminal`

```python
class TerminalStatus(models.TextChoices):
    ACTIVE = "active"
    CLOSED = "closed"

class Terminal(models.Model):
    device = models.ForeignKey(DeviceIdentifier, on_delete=models.CASCADE)
    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE)
    name = models.CharField(max_length=128)  # display label, e.g. "powershell"
    shell = models.CharField(max_length=32, default="powershell")  # powershell | cmd
    cwd = models.TextField()  # absolute path at create time; server chdirs on spawn
    cols = models.PositiveSmallIntegerField(default=80)
    rows = models.PositiveSmallIntegerField(default=24)
    pid = models.IntegerField(null=True, blank=True)  # OS process id while status=active
    status = models.CharField(max_length=16, choices=TerminalStatus.choices, default=TerminalStatus.ACTIVE)
    last_used = models.DateTimeField(auto_now=True)  # bumped on WS I/O, exec, attach
    created_at = models.DateTimeField(auto_now_add=True)
```

Rules:

- Sessions are **local shells only** — spawned on the Windows host by Django; no outbound SSH, no `cloudflared` on clients.
- `cwd` defaults to `workspace.absolute_path` on create; server runs `cd` into that directory before handing control to the PTY.
- `status=active` while PTY is running; set `closed` when the process exits, client deletes, or idle TTL fires.
- `last_used` updates on: WebSocket connect, `input`/`output`, `POST /terminals/{id}/exec/`, and successful `resize`.
- One device may have many terminals; Flutter lists via REST and attaches one WebSocket per open tab.
- `DELETE /terminals/{id}/` kills the PTY (if `active`) and sets `status=closed` (row retained until optional purge).

### Idle terminal cleanup (1 hour)

Constant: `TERMINAL_IDLE_TTL = timedelta(hours=1)`.

**Every Terminal REST handler** calls `close_stale_terminals(device, workspace_id)` before doing work:

```python
def close_stale_terminals(*, device: DeviceIdentifier, workspace_id: int | None = None) -> int:
    cutoff = timezone.now() - settings.TERMINAL_IDLE_TTL
    qs = Terminal.objects.filter(
        device=device,
        status=TerminalStatus.ACTIVE,
        last_used__lt=cutoff,
    )
    if workspace_id is not None:
        qs = qs.filter(workspace_id=workspace_id)
    closed = 0
    for terminal in qs:
        PtyManager.kill(terminal.pid)
        terminal.pid = None
        terminal.status = TerminalStatus.CLOSED
        terminal.save(update_fields=["pid", "status"])
        closed += 1
    return closed
```

Apply in: `GET/POST /terminals/`, `GET/PATCH/DELETE /terminals/{id}/`, `POST /terminals/{id}/exec/`, and at the start of `TerminalConsumer.connect()`.

- Stale terminals are **closed** (PTY killed), not deleted — list endpoints may filter `status=active` by default with `?include_closed=1` optional.
- WebSocket attach to a terminal closed by TTL → server sends `error` `{ "code": "terminal_closed", "message": "idle timeout" }` and closes with `4403`.

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

### Terminals (HTTP — create, list, manage, one-shot exec)

All routes require `X-Workspace-Id` (or `workspace_id` in body). **Each handler runs `close_stale_terminals()` first** (1 h idle). Interactive I/O uses WebSocket (below).

| Method | Path | Body | Response |
| --- | --- | --- | --- |
| GET | `/terminals/` | — | `[{ "id", "name", "shell", "cwd", "status", "pid", "cols", "rows", "last_used", "created_at" }]` — default `status=active` only; `?include_closed=1` for all |
| POST | `/terminals/` | `{ "name?", "shell?", "cwd?", "cols?", "rows?" }` | `{ "id", ... }` — creates row `status=active`; PTY starts on first WebSocket connect |
| GET | `/terminals/{id}/` | — | Terminal detail; `404` if closed and not `include_closed` |
| PATCH | `/terminals/{id}/` | `{ "name", "cols", "rows" }` | Rename or resize metadata (live resize via WS preferred); `409` if `status=closed` |
| DELETE | `/terminals/{id}/` | — | Kill PTY if `active`, set `status=closed` |
| POST | `/terminals/{id}/exec/` | `{ "command", "timeout_ms?", "cwd?" }` | One-shot command; bumps `last_used`; `409` if `status=closed` |

**`POST /terminals/` defaults:**

| Field | Default |
| --- | --- |
| `name` | `shell` value or `"Terminal N"` |
| `shell` | `"powershell"` |
| `cwd` | active workspace `absolute_path` |
| `cols` / `rows` | `80` / `24` |

**`POST /terminals/{id}/exec/`** — run a single command without opening the interactive WebSocket (agent helpers, quick checks):

Request:

```json
{ "command": "git status --short", "timeout_ms": 30000, "cwd": "C:/dev/project" }
```

Response:

```json
{
  "exit_code": 0,
  "stdout": "...",
  "stderr": "",
  "duration_ms": 142
}
```

- Spawns `shell -NoProfile -Command` (PowerShell) or `cmd /c` in `cwd` under workspace sandbox.
- Does not require an active WebSocket; may reuse an idle session row or spawn ephemeral subprocess.
- `timeout_ms` default `30000`; `408` on timeout with partial output.

PTY attach/detach and streaming are **not** HTTP — use `/ws/terminals/{id}/`.

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

**Auth:** same as other sockets — `api_key` + `device_hash` + `workspace_id` in query or first frame.

**Lifecycle:**

1. Handler or consumer calls `close_stale_terminals()` (idle > 1 h → kill PTY, `status=closed`).
2. Client opens WebSocket after `POST /terminals/` (or reconnects to existing `id` with `status=active`).
3. Server spawns ConPTY (`pywinpty`) if `pid` is null: `shell` from row, `cwd` = workspace path; sets `pid`, `status=active`, `last_used=now`.
4. Server sends `attached` with `{ "cols", "rows", "cwd", "shell", "pid", "status" }`.
5. Bidirectional streaming until process exit, `DELETE`, or idle TTL.
6. On PTY exit: `status=closed`, `pid=null`; server sends `exit` `{ "code" }`.

| Client → server | Payload |
| --- | --- |
| `auth` | `{ "api_key", "device_hash", "workspace_id" }` if not in middleware |
| `input` | `{ "data": "<base64>" }` — keystrokes/paste; bumps `last_used` |
| `resize` | `{ "cols", "rows" }` — bumps `last_used` |
| `signal` | `{ "name": "SIGINT" }` — optional interrupt |

| Server → client | Payload |
| --- | --- |
| `attached` | `{ "cols", "rows", "cwd", "shell", "pid", "status" }` |
| `output` | `{ "data": "<base64>" }` — PTY stdout+stderr combined; bumps `last_used` |
| `exit` | `{ "code" }` — then `status=closed` on server |
| `error` | `{ "code", "message" }` — e.g. `terminal_closed` after idle TTL |

**Implementation sketch:**

```python
class TerminalConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        session = await self.get_session()
        self.pty = await PtyManager.spawn(
            shell=session.shell,
            cwd=session.workspace.absolute_path,
            cols=session.cols,
            rows=session.rows,
        )
        await self.accept()
        await self.send_json({"type": "attached", ...})
        asyncio.create_task(self.pump_pty_output())

    async def receive_json(self, content):
        if content["type"] == "input":
            self.pty.write(base64.b64decode(content["data"]))
        elif content["type"] == "resize":
            self.pty.set_size(content["cols"], content["rows"])
```

- Run PTY read loop in a thread or `asyncio.to_thread` — Windows ConPTY is blocking.
- On disconnect, **keep PTY running** (`status` stays `active`) unless `DELETE` or idle TTL fires — user can reattach and refresh `last_used`.
- Mobile app uses `ghostty_vte_flutter` or `xterm` — decode `output` frames into the terminal view.

**Public access:** clients connect to `wss://{SERVER_DOMAIN}/ws/terminals/{id}/` through the same HTTPS tunnel as the REST API. No separate SSH hostname or client-side tunnel binary.

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
| 409 | `terminal_closed` | Terminal `status=closed` |
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
