# Repository structure plan

Definition document for the **ai-maxx-ide** monorepo. This file is the source of truth for top-level layout, deployment boundaries, and how the mobile client talks to the Windows-hosted backend.

## Intent

A Windows workstation runs the **server** (Django + Channels + Cursor SDK + remote desktop + local terminal PTYs). A **Flutter mobile app** connects over **HTTPS/WSS** through a **Cloudflare Tunnel** (`scripts/windows/`). Container packaging lives under `docker/`.

```
ai-maxx-ide/
├── app/                          # Flutter mobile IDE client
├── server/                       # Django ASGI backend (API + WebSockets)
├── docker/                       # Compose, images, deployment helpers
├── scripts/
│   └── windows/
│       ├── setup_cloudflare_tunnel.bat  # Windows entry point
│       ├── setup_cloudflare_tunnel.py   # SERVER_DOMAIN → :8000 only
│       ├── start_services.bat
│       └── README.md
├── docs/
│   ├── designs/design.md         # Visual language (VS Code dark workbench)
│   ├── wireframes/wireframes_v4.html
│   ├── third-party-docs/cursor-sdk.md
│   └── plan/                     # ← implementation definitions (this folder)
├── sample.env                    # Env template — copy to .env (never commit .env)
├── .gitignore
```

## Runtime topology

```mermaid
flowchart LR
  subgraph mobile [Flutter app]
    UI[Wireframe screens]
    LocalIdx[Local SQLite index]
  end

  subgraph edge [Public HTTPS edge]
    AppHost[app.example.com]
  end

  subgraph win [Windows host]
    Django[Django + Channels]
    Cursor[Cursor SDK local agent]
    Remote[aiortc screen + pynput input]
    PTY[ConPTY shells]
    Workspaces[Exposed directories]
  end

  UI -->|HTTPS + WSS + API key + device hash| AppHost
  AppHost --> Django
  Django --> Cursor
  Django --> Remote
  Django --> PTY
  Django --> Workspaces
```

| Surface | Protocol | Purpose |
| --- | --- | --- |
| REST API | HTTPS | Auth, workspaces, files, git, search, terminal CRUD + exec |
| Agent socket | WSS | Cursor agent message stream |
| Remote socket | WSS + WebRTC | Screen relay signaling + input events |
| Terminal socket | WSS | Interactive local shell PTY (create/manage via REST) |

**No raw SSH ingress.** Terminals use WSS on `SERVER_DOMAIN`. Tunnel script exposes API/WSS only.

## `scripts/windows/`

### `setup_cloudflare_tunnel.bat`

Windows entry point. Re-launches elevated when needed (cloudflared install + optional Windows service). Reads **`{repo}/.env`**.

| Source in `.env` | Tunnel ingress |
| --- | --- |
| `SERVER_DOMAIN` | `http://127.0.0.1:{BIND_PORT}` |
| `TUNNEL_EXTRA_INGRESS` (JSON) | Additional `{hostname, service}` pairs |

Responsibilities:

1. Download/install `cloudflared.exe` to `C:\cloudflared` + machine `PATH`.
2. Cloudflare login if `~/.cloudflared/cert.pem` missing.
3. Create named tunnel (`TUNNEL_NAME`) + write `~/.cloudflared/config.yml`.
4. DNS route for `SERVER_DOMAIN` (+ extras).
5. Optional `cloudflared` Windows service when `INSTALL_CLOUDFLARED_SERVICE=true`.

**Production:** Django ASGI on `127.0.0.1:{BIND_PORT}` (default `8000`):

```bat
cd server
uvicorn config.asgi:application --host 127.0.0.1 --port 8000
cloudflared tunnel run ai-maxx-ide
```

## Public exposure

| Hostname | Backend |
| --- | --- |
| `SERVER_DOMAIN` | `http://127.0.0.1:8000` (Django ASGI) |

## `docker/`

Docker is for **repeatable server deployment** on Windows/Linux hosts that support containers. The mobile app does not run in Docker.

```
docker/
├── Dockerfile.server          # Python 3.12 slim + server deps + cursor-sdk bridge
├── docker-compose.yml         # server + redis (channel layer) + optional coturn
├── .env.docker.example
└── README.md
```

| Service | Image / role |
| --- | --- |
| `server` | Django ASGI via `uvicorn server.asgi:application` |
| `redis` | Django Channels layer + session cache |
| `coturn` (optional) | TURN for WebRTC when symmetric NAT blocks P2P |

**Windows host reality:** Screen capture (`mss`) and input injection (`pynput`) require host desktop access. For full Remote tab fidelity, run the server **on the bare Windows machine** (or a Windows VM with GPU/desktop session), not inside a headless Linux container. Docker profile is best for API-only dev or Linux staging without remote desktop.

## `server/`

```
server/
├── manage.py
├── pyproject.toml              # or requirements.txt
├── config/
│   ├── settings/
│   │   ├── base.py
│   │   ├── local.py
│   │   └── production.py
│   ├── asgi.py                 # ProtocolTypeRouter: HTTP + WebSocket
│   ├── urls.py
│   └── wsgi.py                 # unused in production; ASGI only
├── core/
│   ├── middleware.py           # API key + device hash gate
│   ├── authentication.py       # DRF auth classes
│   ├── models.py               # DeviceIdentifier, Workspace, AgentMessage
│   ├── permissions.py
│   └── utils/
│       ├── paths.py            # exposed directory validation
│       └── hashing.py
├── agents/
│   ├── consumers.py            # Agent WebSocket consumer
│   ├── cursor_bridge.py        # cursor-sdk AsyncClient wrapper
│   └── serializers.py
├── files/
│   ├── views.py                # files_by_path, sync_workspace, file download
│   └── tree.py
├── gitapp/
│   ├── views.py                # status, stage, commit, branches, log
│   └── runner.py               # subprocess git with workspace cwd
├── terminals/
│   ├── consumers.py            # PTY WebSocket consumer
│   ├── pty_manager.py          # ConPTY spawn, resize, kill
│   ├── views.py                # REST CRUD + exec
│   └── models.py               # Terminal
├── remote/
│   ├── consumers.py            # WebRTC signaling + input WS
│   ├── screen.py               # mss + aiortc VideoStreamTrack
│   └── input_executor.py       # pynput combo execution
└── tests/
```

### Server `.env` (required keys)

Copy `sample.env` → `.env` at repo root.

| Variable | Used by | Description |
| --- | --- | --- |
| `SERVER_DOMAIN` | tunnel, app, server | Public API hostname |
| `TUNNEL_NAME` | tunnel | cloudflared tunnel name |
| `BIND_HOST` | server | Local bind address (default `127.0.0.1`) |
| `BIND_PORT` | tunnel, server | Local bind port (default `8000`) |
| `TUNNEL_EXTRA_INGRESS` | tunnel | Optional JSON `[{hostname, service}, ...]` |
| `INSTALL_CLOUDFLARED_SERVICE` | tunnel | `true` to install cloudflared as Windows service |
| `CURSOR_API_KEY` | Cursor SDK user/service key |
| `API_KEY` | Shared secret mobile clients send as `X-API-Key` |
| `EXPOSED_DIRECTORIES_ABSOLUTE_PATHS` | JSON array of allowed workspace roots |
| `DJANGO_SECRET_KEY` | Standard Django secret |
| `REDIS_URL` | Channels layer (if not in-memory dev) |
| `DATABASE_URL` | SQLite dev; Postgres prod optional |

## `app/`

```
app/
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   ├── theme/
│   │   ├── workbench_theme.dart    # maps design.md tokens
│   │   ├── typography.dart
│   │   └── codicons.dart           # vendored font + icon map
│   ├── core/
│   │   ├── api/                    # REST client (dio)
│   │   ├── ws/                     # WebSocket base + reconnect
│   │   ├── auth/                   # API key + device registration
│   │   ├── db/                     # sqflite settings + file index
│   │   └── device_identifier.dart  # SHA-256 hardware hash
│   ├── features/
│   │   ├── shell/                  # bottom nav, hamburger gate
│   │   ├── auth/                   # API key modal
│   │   ├── workspace/              # menu, tree, open workspace
│   │   ├── projects/               # Screen 1: search, agent, composer
│   │   ├── terminals/              # Screen 2
│   │   ├── remote/                 # Screen 3
│   │   └── menu/                   # Screens 4–5 workspace + git
│   └── widgets/                    # shared workbench components
├── assets/
│   ├── fonts/
│   │   ├── codicon.ttf
│   │   └── UbuntuMono-Regular.ttf
│   └── icons/                      # optional file icon theme assets
└── test/
```

## Cross-cutting concerns

### Authentication model

Every HTTP and WebSocket request carries:

| Header / param | Value |
| --- | --- |
| `X-API-Key` | Server `API_KEY` |
| `X-Device-Identifier` | SHA-256 hash from Flutter `getSystemHashIdentifier()` |

Device must be registered via `POST /api/devices/register/` before other endpoints succeed.

### Workspace gate (app UX)

Until **authenticated** and **workspace selected**, the shell shows:

1. Hamburger menu only (workspace picker + directory tree).
2. Blocking **Authenticate** affordance (API key modal).
3. No Projects search/agent, Terminals, or Remote tabs in active state.

After `POST /api/workspaces/` + client-side Cursor workspace bind, enable full tab strip per wireframes.

### File sync policy

| Size | Behavior |
| --- | --- |
| ≤ 1 MB | Background sync into local SQLite cache on workspace open |
| > 1 MB | Metadata only locally; explicit user confirm in search UI before download |

### Search strategy

| Mode | Primary | Fallback |
| --- | --- | --- |
| File name search | Local SQLite index (synced tree) | `GET /api/search/files?q=` |
| Grep | Local ripgrep/grep via `process` if indexed content exists | `POST /api/search/grep` on server |

### Reference documents

| Doc | Role |
| --- | --- |
| [design.md](../designs/design.md) | Color, typography, component language |
| [wireframes_v4.html](../wireframes/wireframes_v4.html) | Per-screen design + working behavior |
| [cursor-sdk.md](../third-party-docs/cursor-sdk.md) | Agent streaming API |
| [backend.md](./backend.md) | API + WebSocket contracts |
| [app.md](./app.md) | Flutter screen implementation |
| [package-docs.md](./package-docs.md) | Dependency choices |

## Implementation phases

| Phase | Deliverable |
| --- | --- |
| P0 | `scripts/windows` tunnel + Django skeleton + device auth |
| P1 | Workspace/files/git REST + hamburger menu in Flutter |
| P2 | Agent WebSocket + Projects tab composer |
| P3 | Terminals REST + PTY WebSocket |
| P4 | Remote WebRTC screen + input staging |
| P5 | Local search index + grep + file reference UX |
