import 'package:flutter_test/flutter_test.dart';

import 'package:ai_maxx_ide/core/models/route_node.dart';

void main() {
  test('flattenRouteTree drops children', () {
    const tree = [
      RouteNode(
        path: '/root',
        asset: 'root',
        pathType: 'folder',
        children: [
          RouteNode(
            path: '/root/a.txt',
            asset: 'a.txt',
            pathType: 'file',
          ),
        ],
      ),
    ];
    final flat = flattenRouteTree(tree);
    expect(flat.length, 2);
    expect(flat.every((n) => n.children.isEmpty), isTrue);
  });

  test('sequentialMatch behaves like VS Code quick open', () {
    expect(sequentialMatch('ProjectsScreen.dart', 'psd'), isTrue);
    expect(sequentialMatch('ProjectsScreen.dart', 'xyz'), isFalse);
  });

  test('searchByName returns files only', () {
    const entries = [
      RouteNode(path: '/a', asset: 'a', pathType: 'folder'),
      RouteNode(path: '/a/main.dart', asset: 'main.dart', pathType: 'file'),
    ];
    final hits = searchByName(entries, 'main');
    expect(hits.length, 1);
    expect(hits.first.asset, 'main.dart');
  });
}
