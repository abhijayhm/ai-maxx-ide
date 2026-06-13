# Flutter Android debug — reference

## Project constants

| Item | Value |
|------|-------|
| Flutter root | `app/` |
| Android package | `com.aimaxx.ai_maxx_ide` |
| Server URL (default) | `https://aimaxx.organisationapp.online` |
| API key (must match `.env`) | `change-me-to-a-long-random-secret` |
| WS base | `wss://{host}/api/ws/` |
| Commands doc | `docs/commands.txt` |
| Auth/WS rules | `.cursor/rules/important-basics.mdc` |

## MCP servers

| Server | Role |
|--------|------|
| `user-dart` | DTD, errors, widget tree, hot reload/restart, analyze |
| `user-Mobile_MCP` | Device UI a11y tree, gestures, launch, crashes |
| `user-chrome-devtools` | Web only — **not** for Android APK |

Always read tool JSON schema under `mcps/<server>/tools/` before first use in a session.

## Dart MCP tools

### `dtd`

| command | Purpose |
|---------|---------|
| `listDtdUris` | Find DTD instances (prefer IDE/working-dir match) |
| `connect` | Attach to DTD (`uri` required) |
| `listConnectedApps` | Get `appUri` for other tools |
| `disconnect` | Clean up |

### `get_runtime_errors`

- Requires active DTD connection.
- `clearRuntimeErrors: true` before re-read after fix.
- `appUri` if multiple apps connected.

### `widget_inspector`

| command | Args | Notes |
|---------|------|-------|
| `get_widget_tree` | `summaryOnly: true` preferred | Full tree is huge |
| `get_selected_widget` | — | After selection mode |
| `set_widget_selection_mode` | `enabled: true/false` | Rarely needed |

### `hot_reload` / `hot_restart`

- Reload: UI + method changes, keeps state.
- Restart: const/globals/providers/init/dispose.
- Both need DTD; pass `appUri` if multiple apps.

### `analyze_files`

```json
{
  "roots": [{
    "root": "file:///C:/all-files/misc/ai-maxx-ide/app",
    "paths": ["lib/features/projects/projects_screen.dart"]
  }]
}
```

### `flutter_driver_command` (optional precision)

Use after `get_widget_tree`. Common:

| command | finder |
|---------|--------|
| `tap` | `ByText`, `BySemanticsLabel`, `ByValueKey` |
| `enter_text` | focus field first |
| `scroll` | `dx`/`dy`/`duration`/`frequency` strings |
| `waitFor` | wait for widget |
| `get_diagnostics_tree` | `diagnosticsType: widget`, small `subtreeDepth` |

Avoid `screenshot` unless visual regression required.

### Other

- `pub` — dependencies
- `read_package_uris` / `rip_grep_packages` — package source lookup
- `roots` — allowed analyze roots

## Mobile MCP tools

### Device lifecycle

| Tool | Use |
|------|-----|
| `mobile_list_available_devices` | Get `device` id |
| `mobile_launch_app` | Foreground app |
| `mobile_terminate_app` | Force stop |
| `mobile_list_apps` | Find package names |

### UI tree (primary)

**`mobile_list_elements_on_screen`** — returns elements with:

- Display text / accessibility label
- Bounds → derive tap `(x, y)` at center
- **Do not cache** — call again after each navigation

### Gestures

| Tool | Use |
|------|-----|
| `mobile_click_on_screen_at_coordinates` | Tap |
| `mobile_double_tap_on_screen` | Double tap |
| `mobile_long_press_on_screen_at_coordinates` | Long press |
| `mobile_swipe_on_screen` | Scroll |
| `mobile_type_keys` | Text + optional submit |
| `mobile_press_button` | `BACK`, `HOME`, etc. |

### Diagnostics (heavy — use sparingly)

| Tool | Use |
|------|-----|
| `mobile_list_crashes` / `mobile_get_crash` | Native crash reports |
| `mobile_take_screenshot` | Last resort |
| `mobile_start_screen_recording` | Repro video for user only |

## Shell fallbacks (when MCP insufficient)

```powershell
# Device
adb devices
cd app; flutter devices
cd app; flutter run -d DEVICE_ID

# Logs (structured text, not screenshots)
adb logcat -d | Select-String -Pattern "flutter|aimaxx" | Select-Object -Last 80

# Static tests
cd app; flutter test
cd app; flutter analyze
cd server; python -m pytest tests/ -q
```

## App architecture (debug hints)

| Area | Key files |
|------|-----------|
| Session/auth | `app/lib/core/providers/app_providers.dart` |
| Sync WS | `workspace_sync_service.dart`, `sync_provider.dart` |
| Agent WS | `agent_client.dart`, `agent_provider.dart` |
| Remote WS/WebRTC | `remote_client.dart`, `remote_provider.dart` |
| WS client | `app/lib/core/ws/ws_client.dart` |
| Config/URLs | `app/lib/core/config/app_config.dart` |

**WS 502 pattern:** sync WS open + Cursor bind blocks Daphne → agent/remote fail at Cloudflare. Wait for sync complete; check server log for `CONNECT` vs `HANDSHAKING` only.

## Improving debuggability (when fixing UI)

Add only when it helps automation:

- `Semantics(label: '…')` on icon-only controls
- `Key('…')` / `ValueKey` on critical buttons
- Keep visible `Text` on tab labels (already: Projects, Terminals, Remote)

## Token budget checklist

Before calling a tool, ask:

1. Can `get_runtime_errors` answer this?
2. Can `mobile_list_elements_on_screen` replace a screenshot?
3. Can `widget_inspector` with `summaryOnly: true` replace full tree?
4. Can I `analyze_files` one file instead of whole project?
5. Is server-side log enough for 502/API errors?

If yes to any — use that first.
