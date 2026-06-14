/// REST + WebSocket endpoint registry (mirrors `common/urls.json`).
class ApiManifest {
  ApiManifest._();

  static const apiBasePath = '/api/';
  static const wsBasePath = '/api/ws/';

  static const health = 'health/';
  static const devicesRegister = 'devices/register/';
  static const devicesIdentifier = 'devices/identifier/';
  static const exposedRoutesTree = 'exposed_routes_tree/';
  static const workspaceOpen = 'workspaces/';
  static String workspaceTree(int id) => 'workspaces/$id/tree/';

  static const terminalsList = 'terminals/';
  static String terminalDetail(int id) => 'terminals/$id/';
  static String terminalExec(int id) => 'terminals/$id/exec/';
  static String terminalIo(int id) => 'terminals/$id/io/';

  static const wsWatchdog = 'watchdog/';
  static const wsIdeSearch = 'ide_search/';
  static const wsGit = 'git/';
  static const wsRemote = 'remote/';
  static String wsTerminal(int id) => 'terminals/$id/';

  static const restPaths = {
    'health': health,
    'devices_register': devicesRegister,
    'devices_identifier': devicesIdentifier,
    'exposed_routes_tree': exposedRoutesTree,
    'workspace_open': workspaceOpen,
    'workspace_tree': 'workspaces/{workspace_id}/tree/',
  };
}
