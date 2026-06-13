/// API surface — keep in sync with [common/urls.json] at repo root.
class ApiManifest {
  ApiManifest._();

  static const String apiBasePath = '/api/';
  static const String wsBasePath = '/api/ws/';

  // Core
  static const health = 'health/';
  static const devicesRegister = 'devices/register/';
  static const devicesIdentifier = 'devices/identifier/';
  static const workspaces = 'workspaces/';

  // Files
  static const filesRoots = 'files/roots/';
  static const filesByPath = 'files/by-path/';
  static const filesDownload = 'files/download/';
  static const filesMkdir = 'files/mkdir/';
  static const filesTouch = 'files/touch/';

  // Search
  static const searchFiles = 'search/files/';
  static const searchGrep = 'search/grep/';

  // Agent REST
  static const agentMessages = 'agent/messages/';
  static const agentStop = 'agent/stop/';
  static const agentStatus = 'agent/status/';

  // Terminals REST
  static const terminals = 'terminals/';

  // Git REST
  static const gitStatus = 'git/status/';
  static const gitStage = 'git/stage/';
  static const gitUnstage = 'git/unstage/';
  static const gitDiscard = 'git/discard/';
  static const gitStash = 'git/stash/';
  static const gitCommit = 'git/commit/';
  static const gitSync = 'git/sync/';
  static const gitExec = 'git/exec/';
  static const gitBranches = 'git/branches/';
  static const gitCheckout = 'git/checkout/';
  static const gitLog = 'git/log/';

  // WebSocket relative paths (under wsBasePath)
  static const wsAgent = 'agent/';
  static String wsSync(int workspaceId) => 'sync/$workspaceId/';
  static String wsTerminal(int terminalId) => 'terminals/$terminalId/';
  static const wsRemote = 'remote/';

  static String workspaceSync(int workspaceId) =>
      'workspaces/$workspaceId/sync/';
  static String workspaceBindCursor(int workspaceId) =>
      'workspaces/$workspaceId/bind-cursor/';
  static String terminalDetail(int id) => 'terminals/$id/';
  static String terminalExec(int id) => 'terminals/$id/exec/';

  /// All REST path keys from common/urls.json (for tests).
  static const restPaths = {
    'health': health,
    'devices_register': devicesRegister,
    'workspaces_list': workspaces,
    'files_roots': filesRoots,
    'search_files': searchFiles,
    'search_grep': searchGrep,
    'agent_status': agentStatus,
    'terminals_list': terminals,
    'git_status': gitStatus,
    'git_commit': gitCommit,
    'git_branches': gitBranches,
    'git_log': gitLog,
  };
}
