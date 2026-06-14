class TerminalSession {
  const TerminalSession({
    required this.id,
    required this.name,
    required this.shell,
    required this.cwd,
    required this.status,
    this.pid,
    this.cols = 80,
    this.rows = 24,
  });

  final int id;
  final String name;
  final String shell;
  final String cwd;
  final String status;
  final int? pid;
  final int cols;
  final int rows;

  bool get isActive => status == 'active';

  factory TerminalSession.fromJson(Map<String, dynamic> json) {
    return TerminalSession(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Terminal',
      shell: json['shell'] as String? ?? 'powershell',
      cwd: json['cwd'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      pid: json['pid'] as int?,
      cols: json['cols'] as int? ?? 80,
      rows: json['rows'] as int? ?? 24,
    );
  }
}

class TerminalAttachInfo {
  const TerminalAttachInfo({
    required this.cols,
    required this.rows,
    required this.cwd,
    required this.shell,
    this.pid,
    this.status,
  });

  final int cols;
  final int rows;
  final String cwd;
  final String shell;
  final int? pid;
  final String? status;

  factory TerminalAttachInfo.fromJson(Map<String, dynamic> json) {
    return TerminalAttachInfo(
      cols: json['cols'] as int? ?? 80,
      rows: json['rows'] as int? ?? 24,
      cwd: json['cwd'] as String? ?? '',
      shell: json['shell'] as String? ?? 'powershell',
      pid: json['pid'] as int?,
      status: json['status'] as String?,
    );
  }
}

class TerminalIOLine {
  const TerminalIOLine({
    required this.id,
    required this.direction,
    required this.data,
    required this.createdAt,
  });

  final int id;
  final String direction;
  final String data;
  final String createdAt;

  bool get isOutput => direction == 'output';

  factory TerminalIOLine.fromJson(Map<String, dynamic> json) {
    return TerminalIOLine(
      id: json['id'] as int,
      direction: json['direction'] as String? ?? 'output',
      data: json['data'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}
