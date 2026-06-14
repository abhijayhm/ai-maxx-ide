class AgentSessionInfo {
  const AgentSessionInfo({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory AgentSessionInfo.fromJson(Map<String, dynamic> json) {
    return AgentSessionInfo(
      id: json['id'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  String get label {
    final local = createdAt.toLocal();
    final date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }
}
