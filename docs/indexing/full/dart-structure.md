# Dart App Structure

Flutter client under `app/lib/`. **25 Dart files** (including new `core/ws/ws_client.dart`).

## Tree

```
app/lib/
├── main.dart                          # ProviderScope + runApp
├── app.dart                           # MaterialApp.router, theme
├── core/
│   ├── api/api_client.dart            # Dio REST client (auth headers)
│   ├── auth/auth_repository.dart      # Register device, workspaces
│   ├── config/app_config.dart         # Server URL, API key, ws base URL
│   ├── db/app_database.dart           # SQLite: settings + file index
│   ├── device_identifier.dart         # Platform id → SHA256 hash
│   ├── providers/
│   │   ├── app_providers.dart         # Session, API client, auth repo
│   │   ├── file_search_provider.dart  # Search indexed files
│   │   └── sync_provider.dart         # Background WS sync notifier
│   ├── sync/
│   │   ├── sync_models.dart           # SyncTreeNode, SyncProgress
│   │   └── workspace_sync_service.dart # WS sync orchestration
│   └── ws/ws_client.dart              # JSON WebSocket helper
├── features/
│   ├── menu/
│   │   ├── workspace_menu_screen.dart # Auth + workspace picker
│   │   └── git_menu_screen.dart       # Git stub
│   ├── onboarding/auth_modal.dart     # API key registration sheet
│   ├── projects/projects_screen.dart  # File search (local index)
│   ├── remote/remote_screen.dart      # WebRTC stub
│   ├── shell/workbench_scaffold.dart  # Header, tabs, sync status
│   └── terminals/terminals_screen.dart
├── routing/app_router.dart            # GoRouter + session redirect
├── theme/
│   ├── workbench_colors.dart
│   └── workbench_theme.dart
└── widgets/workbench_search_field.dart  # Used on Projects tab only
```

## Entry & shell

| File | Responsibility |
|------|----------------|
| `main.dart` | Boots `ProviderScope`, calls `runApp(AiMaxxIdeApp())` |
| `app.dart` | `MaterialApp.router` with `appRouterProvider`, dark workbench theme |
| `workbench_scaffold.dart` | Top bar (**AI Maxx IDE**), bottom tabs (Projects / Terminals / Remote), sync status text |

## Routing (`app_router.dart`)

- **Provider:** `appRouterProvider` → `GoRouter`
- **Guard:** unauthenticated or no workspace → `/menu/workspace`
- **Shell tabs:** `/projects`, `/terminals`, `/remote` inside `WorkbenchScaffold`
- **Overlays:** `/menu/workspace`, `/menu/git` (slide from left)

## State (Riverpod)

| Provider | Type | Role |
|----------|------|------|
| `appConfigProvider` | `Provider` | `AppConfig` (server URL, API key) |
| `appDatabaseProvider` | `FutureProvider` | Opens SQLite |
| `deviceIdentifierProvider` | `Provider` | Device hash service |
| `sessionProvider` | `AsyncNotifierProvider` | Auth + active workspace snapshot |
| `apiClientProvider` | `FutureProvider` | Dio with `X-API-Key`, `X-Device-Identifier`, `X-Workspace-Id` |
| `authRepositoryProvider` | `FutureProvider` | Workspace list/open/set/register |
| `workspaceSyncProvider` | `NotifierProvider` | `SyncProgress` from background WS sync |
| `fileSearchProvider(query)` | `Provider.family` | SQLite `LIKE` search |
| `indexedFileStatsProvider` | `Provider` | Indexed vs content-synced counts |

### Session → sync

`SessionNotifier` triggers sync when:

- App starts with ready session (`_kickoffBackgroundSync`)
- User selects workspace (`setWorkspace`)
- User opens new workspace (`openWorkspace`)

`workspaceSyncProvider.notifier.start(id)` is **non-blocking**.

## Sync client flow

```
workspaceSyncProvider.start(workspaceId)
    → WorkspaceSyncService.syncWorkspace()
        → WsClient.connect('sync/{id}/')
        → send {type: start}
        ← ready, sync_started, bind_cursor (ignored)
        ← metadata {tree, files_total}  → SQLite index replace
        ← files {files[], files_done}     → SQLite content update (batches)
        ← complete
```

## Local database (`app_database.dart`)

Tables:

- **settings** — `api_key`, `device_hash`, `active_workspace_id`
- **files** — per-workspace index: `path`, `name`, `type`, `size`, `sync_policy`, `content`, `content_hash`, `synced_at`

Search runs entirely on-device after sync.

## Config defaults (`app_config.dart`)

```dart
defaultServerUrl = 'https://aimaxx.organisationapp.online'
webSocketBaseUrl → wss://aimaxx.organisationapp.online/ws/
apiBaseUrl       → https://aimaxx.organisationapp.online/api/
```

## Dependencies (`pubspec.yaml`)

| Package | Use |
|---------|-----|
| `flutter_riverpod` | State |
| `go_router` | Navigation |
| `dio` | REST |
| `web_socket_channel` | WS sync, future terminals/agent |
| `sqflite` | File index |
| `flutter_secure_storage` | (reserved) |
| `crypto` | Content hashes |
| `device_info_plus` | Device registration |

## Feature maturity

| Feature | Status |
|---------|--------|
| Auth / workspaces | Working |
| Workspace index sync | Working (WebSocket) |
| Projects file search | Working (local) |
| Terminals | UI stub |
| Remote | UI stub |
| Git menu | UI stub |
| Agent composer | Not wired in app yet |
