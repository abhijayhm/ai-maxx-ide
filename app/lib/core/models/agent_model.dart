class AgentModelInfo {
  const AgentModelInfo({
    required this.id,
    required this.displayName,
  });

  final String id;
  final String displayName;

  factory AgentModelInfo.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    return AgentModelInfo(
      id: id,
      displayName: json['display_name'] as String? ?? id,
    );
  }
}
