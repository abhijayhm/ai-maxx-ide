/// Route tree node from `exposed_routes_tree` / `workspace_tree`.
class RouteNode {
  const RouteNode({
    required this.path,
    required this.asset,
    required this.pathType,
    this.children = const [],
  });

  final String path;
  final String asset;
  final String pathType;
  final List<RouteNode> children;

  bool get isFolder => pathType == 'folder';
  bool get isFile => pathType == 'file';

  factory RouteNode.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'] as List<dynamic>? ?? [];
    return RouteNode(
      path: json['path'] as String? ?? '',
      asset: json['asset'] as String? ?? '',
      pathType: json['path_type'] as String? ?? 'file',
      children: rawChildren
          .map((c) => RouteNode.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJsonFlat() => {
        'path': path,
        'asset': asset,
        'path_type': pathType,
      };

  Map<String, dynamic> toJson() => {
        'path': path,
        'asset': asset,
        'path_type': pathType,
        'children': children.map((c) => c.toJson()).toList(),
      };
}

/// Depth-first flatten (no children in output).
List<RouteNode> flattenRouteTree(List<RouteNode> roots) {
  final flat = <RouteNode>[];
  void walk(RouteNode node) {
    flat.add(
      RouteNode(
        path: node.path,
        asset: node.asset,
        pathType: node.pathType,
      ),
    );
    for (final child in node.children) {
      walk(child);
    }
  }

  for (final root in roots) {
    walk(root);
  }
  return flat;
}

/// VS Code-style sequential character match on [asset] name.
bool sequentialMatch(String asset, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    return true;
  }
  final a = asset.toLowerCase();
  var qi = 0;
  for (var i = 0; i < a.length && qi < q.length; i++) {
    if (a[i] == q[qi]) {
      qi++;
    }
  }
  return qi == q.length;
}

List<RouteNode> searchByName(List<RouteNode> entries, String query) {
  final q = query.trim();
  if (q.isEmpty) {
    return const [];
  }
  return entries
      .where((e) => e.isFile && sequentialMatch(e.asset, q))
      .toList();
}
