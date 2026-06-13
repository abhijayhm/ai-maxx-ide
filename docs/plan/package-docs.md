# Package & dependency reference

Curated libraries for [backend.md](./backend.md) and [app.md](./app.md), with rationale from pub.dev / PyPI research (June 2026). Prefer stable, actively maintained packages with Windows support.

---

## Python — server (`server/`)

### Core framework

| Package | Version pin (guidance) | Role |
| --- | --- | --- |
| `django` | `>=5.0,<6` | Web framework |
| `djangorestframework` | `>=3.15` | REST API |
| `channels` | `>=4.0` | WebSocket consumers |
| `channels-redis` | `>=4.2` | Channel layer (prod) |
| `uvicorn[standard]` | `>=0.30` | ASGI server |
| `django-environ` | `>=0.11` | `.env` loading |
| `httpx` | `>=0.27` | HTTP client (cursor-sdk dep) |

### Cursor agent

| Package | Role |
| --- | --- |
| `cursor-sdk` | Local Cursor agent bridge — see [cursor-sdk.md](../third-party-docs/cursor-sdk.md) |

Notes:

- Requires Python 3.10+; ships `cursor-sdk-bridge` binary in wheel.
- Use `AsyncClient` + `AsyncWebsocketConsumer` (never sync consumer for streaming).
- Pin minor version once first working integration lands (`cursor-sdk==0.1.7` as of research).

### Remote desktop (Screen 3)

| Package | Role | Why |
| --- | --- | --- |
| `aiortc` | WebRTC peer connection, `VideoStreamTrack` | Mature Python WebRTC; pairs with Flutter `flutter_webrtc` |
| `av` (PyAV) | `VideoFrame.from_ndarray` | Required by aiortc for frame encoding |
| `mss` | Fast cross-platform screen capture | Windows `CreateDIBSection` backend; high FPS |
| `numpy` | Buffer manipulation | Frame arrays from mss |
| `pynput` | Mouse + keyboard injection | Combo execution for staged remote input |

**Not chosen:** `pyautogui` — slower, less precise modifier handling; `pynput` has explicit `pressed()` context for combos.

**Screen track pattern:**

- `queue.Queue(maxsize=1)` between mss thread and async `recv()` — prevents latency buildup (aiortc issue #1192).
- Crop frame to width/height multiple of 8 before PyAV encode (PyAV alignment issue #478).

**Signaling:** JSON over Django Channels WS; not raw video over WebSocket.

Optional:

| Package | Role |
| --- | --- |
| `aiohttp` | Standalone signaling server (only if splitting remote service) |

### Terminals (Screen 2)

| Package | Role | Why |
| --- | --- | --- |
| `pywinpty` / `winpty` | Windows ConPTY | Native Windows pseudoterminal for local shells |

Interactive I/O is WebSocket-only; one-shot commands use `POST /api/terminals/{id}/exec/`.

### Files & search

| Package | Role |
| --- | --- |
| `pathspec` | Gitignore-aware walks (optional) |
| `watchdog` | Filesystem watch for index invalidation (optional) |

Server grep: invoke `rg` if on PATH, else `grep -R` — no `ripgrep-py` binding required.

### Git

Use system `git` via `subprocess` — matches user config, credentials, and hooks. No extra package.

---

## Flutter — app (`app/`)

### Core

| Package | Role |
| --- | --- |
| `flutter` | SDK `>=3.22` |
| `dio` | REST client, interceptors, download progress |
| `web_socket_channel` | WSS with reconnect wrapper |
| `go_router` | Tab + full-screen menu routes |
| `flutter_riverpod` | State / DI |
| `sqflite` | Local settings + file index |
| `flutter_secure_storage` | API key storage |
| `path_provider` | Cache dirs |
| `crypto` | SHA-256 device hash |
| `device_info_plus` | Platform identifiers (user snippet) |

### Device identity

User-provided `getSystemHashIdentifier()` uses `device_info_plus` + `crypto` — no extra package.

### UI / theme

| Package | Role |
| --- | --- |
| `google_fonts` | Ubuntu + Ubuntu Mono (match wireframes_v4) |
| Custom asset `codicon.ttf` | Workbench icons — vendored from [vscode-codicons](https://www.npmjs.com/package/vscode-codicons) |

**Codicon in Flutter:** `package:codicon` is **discontinued** on pub.dev. Vendor the font + `IconData` constants (as wireframes_v4 does with CSS).

| Package | Role |
| --- | --- |
| `vscode_material_icon_theme` | File/folder icons in trees |
| `flutter_svg` | If using SVG icon theme assets |

### Code display (read-only chips / previews)

| Package | Role | Why |
| --- | --- | --- |
| `re_editor` + `re_highlight` | Lightweight syntax blocks in agent panel | Matches VS Code-like themes; used in Reqable |
| `duskmoon_code_engine` | Alternative pure-Dart editor | CodeMirror 6 port; good if need inline editor later |

**Not chosen for v1:** `code_forge` — powerful but Rust backend, no Flutter web; overkill for read-only references.

### Terminal emulator (Screen 2)

| Package | Role | Why |
| --- | --- | --- |
| `ghostty_vte_flutter` | Terminal renderer + PTY controller | Modern VT engine; WS transport on web |
| `portable_pty_flutter` | Re-exported by ghostty; WS PTY client | Same API native/web |

**Alternative:** `xterm` (^4.0) — established, 235 likes; use if Ghostty integration blocked on a platform.

Pair with server `WS /ws/terminals/{id}/`.

### Remote desktop (Screen 3)

| Package | Role | Why |
| --- | --- | --- |
| `flutter_webrtc` | `RTCPeerConnection`, `RTCVideoRenderer` | De facto Flutter WebRTC; screen render on mobile |

Signaling JSON over `web_socket_channel`; video via WebRTC track (not MJPEG over WS).

**Platform notes:**

- Android 14+ may need foreground service for screen capture when roles reverse (usually client receives only).
- iOS receives only — no input injection on server from iOS client restrictions on outgoing.

### Search & files (local)

| Package | Role |
| --- | --- |
| `process` | Spawn `rg`/`grep` for local grep mode |
| `mime` | Content-type sniffing for previews |
| `archive` | Optional zip batch download |

**Not chosen:** `flutter_hybrid_search` — FTS5/HNSW overkill for filename + path grep v1.

**Optional later:** `searchlight` for fuzzy in-app index if SQLite LIKE insufficient.

### Selection / UX helpers

| Package | Role |
| --- | --- |
| `flutter_list_selection` or custom | GitHub-style range selection in result list |
| `super_sliver_list` | Performant long file lists |

Range selection may be **custom** `ListView` with `selectedRangeStart/End` state (wireframe requirement).

### Git UI (Screen 5)

No Dart git library — all via REST per backend.md.

### Testing

| Package | Role |
| --- | --- |
| `flutter_test` | Widget tests |
| `mocktail` | Mock repositories |
| `golden_toolkit` | Theme regression |

---

## Docker (`docker/`)

| Image / package | Role |
| --- | --- |
| `python:3.12-slim-bookworm` | Base image |
| `redis:7-alpine` | Channel layer |
| `coturn/coturn` | Optional TURN for WebRTC |

Server image installs: `git`, `ripgrep`, `cursor-sdk` wheel deps. **Does not** include GUI capture — document limitation in compose README.

---

## Version lock strategy

1. **Server:** `requirements.lock` or `uv.lock` generated in CI; pin `cursor-sdk` minor.
2. **App:** `pubspec.lock` committed; monthly `flutter pub upgrade --major-versions` review.
3. **Security:** dependabot for Django + dio; never commit `.env`.

---

## Alternatives considered (summary)

| Area | Chosen | Rejected |
| --- | --- | --- |
| Agent | `cursor-sdk` local | Raw REST `/v1/agents` only |
| Remote video | aiortc + flutter_webrtc | MJPEG HTTP stream (higher latency) |
| Remote input | pynput | pyautogui, SendInput ctypes |
| Terminal access | WSS + ConPTY (`pywinpty`) | External SSH / `asyncssh` |
| Terminal UI | ghostty_vte_flutter | xterm only (acceptable fallback) |
| Workbench icons | vendored codicon | discontinued `codicon` pub package |
| File icons | vscode_material_icon_theme | mixed icon packs |
| Local editor | re_highlight chips | code_forge full editor |
| Search | SQLite + rg + server API | flutter_hybrid_search vectors |

---

## External references

| Resource | URL |
| --- | --- |
| Cursor Python SDK | https://cursor.com/docs/sdk/python |
| Local mirror | [cursor-sdk.md](../third-party-docs/cursor-sdk.md) |
| aiortc docs | https://aiortc.readthedocs.io/ |
| pynput docs | https://pynput.readthedocs.io/ |
| flutter_webrtc | https://pub.dev/packages/flutter_webrtc |
| Django Channels | https://channels.readthedocs.io/ |
| Design language | [design.md](../designs/design.md) |
| Wireframes | [wireframes_v4.html](../wireframes/wireframes_v4.html) |
