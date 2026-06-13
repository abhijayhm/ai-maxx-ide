---
name: flutter-android-debug
description: >-
  Token-efficient Flutter/Android app debug and fix loop using Dart MCP (DTD,
  runtime errors, widget tree, hot reload) and Mobile MCP (Android accessibility
  UI tree, taps, typing). Use when testing or fixing the ai-maxx-ide app, when
  the user mentions Dart MCP, Mobile MCP, Android UI tree, hot reload, runtime
  errors, device testing, or asks to debug/fix the mobile client.
---

# Flutter + Android debug (ai-maxx-ide)

**Goal:** maximum control with minimum tokens. Prefer structured text (errors, trees, logs) over screenshots.

## Token rules (strict)

| Priority | Source | Use for |
|----------|--------|---------|
| 1 | `user-dart` → `get_runtime_errors` | Crashes, asserts, overflow, async errors |
| 2 | `user-dart` → `analyze_files` (changed paths only) | Compile/lint before run |
| 3 | `user-dart` → `widget_inspector` `get_widget_tree` + `summaryOnly: true` | Layout/semantics in Flutter layer |
| 4 | `user-Mobile_MCP` → `mobile_list_elements_on_screen` | What's on device (text, a11y label, x/y) |
| 5 | Shell: server terminal, `curl /api/health/`, pytest | API/WS/backend issues |
| 6 | `hot_reload` → re-check errors | Verify fix cheaply |
| 7 | `hot_restart` | State/const/init/dispose bugs |
| 8 | `mobile_take_screenshot` / driver `screenshot` | **Last resort** — visual-only bugs |

**Never** screenshot to find button coordinates — use `mobile_list_elements_on_screen`.
**Never** guess widget finders — read tree first, then `flutter_driver_command` if needed.
**Do not cache** `mobile_list_elements_on_screen` results — re-list after navigation.

## Bootstrap (once per session)

```
1. user-dart → dtd { command: listDtdUris }
2. user-dart → dtd { command: connect, uri: <IDE DTD if flutter run active> }
3. user-dart → dtd { command: listConnectedApps }  → note appUri
4. user-Mobile_MCP → mobile_list_available_devices → note device id
5. If app not foreground → mobile_launch_app { device, packageName: com.aimaxx.ai_maxx_ide }
```

App must be running via `flutter run -d DEVICE_ID` (from `app/`) for DTD + hot reload.
Backend stack when testing sync/agent/remote: server on `127.0.0.1:8000` + tunnel. See `docs/commands.txt`.

## Standard fix loop

Copy and track:

```
Debug progress:
- [ ] Reproduce (mobile tree or user step)
- [ ] get_runtime_errors (clearRuntimeErrors: true if stale)
- [ ] analyze_files on edited paths
- [ ] Code fix (minimal diff)
- [ ] hot_reload → get_runtime_errors
- [ ] Re-navigate + mobile_list_elements_on_screen to confirm UI
- [ ] hot_restart if stateful; flutter test if logic-only
```

### After every code change

1. `analyze_files` on touched files under `file:///.../app`
2. `hot_reload` with `clearRuntimeErrors: true`
3. `get_runtime_errors` — must be clean before reporting done

### When hot reload is not enough

- Global/const/provider init → `hot_restart`
- Native/plugin/WebRTC → full `flutter run` rebuild
- Server WS/502 → read Daphne log; wait for sync to finish before agent/remote WS

## Symptom → action

| Symptom | First tool | Then |
|---------|------------|------|
| Red screen / exception | `get_runtime_errors` | Read cited `app/lib/...` file |
| Overflow / layout | errors + `widget_inspector` summary tree | Fix constraints; reload |
| Button missing / wrong screen | `mobile_list_elements_on_screen` | Tap by coords from tree |
| Tap does nothing | tree + errors | Check `ref.listen`, provider, `isReady` |
| API 401/403 | code + `.env` API_KEY match | `curl` health + authenticated endpoint |
| WS 502 on agent/remote | server terminal | Sync must finish first; see `.cursor/rules/important-basics.mdc` |
| WebRTC black video | errors + server `REMOTE_WEBRTC_STUB` | Not a screenshot problem |
| Crash on launch | `mobile_list_crashes` → `mobile_get_crash` | Stack trace → fix → restart |

## ai-maxx-ide smoke path (Mobile MCP)

Use element **text/label** from tree; coords only when tapping.

1. **Launch** `com.aimaxx.ai_maxx_ide`
2. **Workspace menu** — register/set API key if tabs disabled
3. **Open workspace** — pick exposed path; wait until sync banner **gone**
4. **Projects** — search field, composer; confirm no agent error panel
5. **Terminals** — list loads (REST 200)
6. **Remote** — connect after sync; video or stub answer

Defer agent/remote WS until sync completes (`workspaceSyncProvider` not active).

## Interaction patterns (Mobile MCP)

```
# Inspect
mobile_list_elements_on_screen { device }

# Tap (use center of element bounds from tree)
mobile_click_on_screen_at_coordinates { device, x, y }

# Type into focused field
mobile_click_on_screen_at_coordinates → mobile_type_keys { device, text, submit }

# Scroll tab bar / long lists
mobile_swipe_on_screen { device, startX, startY, endX, endY }

# Back
mobile_press_button { device, button: "BACK" }
```

Prefer **semantics labels** and visible text over resource ids.

## Flutter layer (Dart MCP)

```
# Compact widget tree (user code only)
widget_inspector { command: get_widget_tree, summaryOnly: true }

# Precise tap/scroll (after tree)
flutter_driver_command { command: tap, finderType: ByText, text: "Projects" }

# Apply fix
hot_reload { clearRuntimeErrors: true }
get_runtime_errors {}
```

For driver commands: read `get_widget_tree` first — use real `ByText`, `BySemanticsLabel`, or `ByValueKey` from tree.

## Backend cross-check (API/WS bugs)

Not replace Mobile/Dart MCP — run in parallel when symptom is network:

```powershell
curl https://aimaxx.organisationapp.online/api/health/
cd server; python -m pytest tests/test_sync_ws.py tests/test_agents_ws.py -q
```

Read active `runserver` terminal for `WebSocket CONNECT` vs `HANDSHAKING` only.

## Report template (after fix)

```markdown
## Fix summary
- **Symptom:** …
- **Root cause:** …
- **Change:** `path/file.dart` — …
- **Verified:** hot_reload clean; mobile tree shows …; errors empty
```

## When referred

If the user invokes this skill or asks to test/fix the app:

1. Read this file fully.
2. Run bootstrap if DTD/device unknown.
3. Execute standard fix loop — do not stop at analysis.
4. For tool schemas and project constants, see [reference.md](reference.md).
