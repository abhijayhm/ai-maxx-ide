import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/route_node.dart';
import '../core/providers/workspace_tree_explorer_provider.dart';
import '../theme/workbench_colors.dart';
import '../theme/workbench_theme.dart';

/// Workspace file/folder tree with long-press path selection for agent context.
class WorkspaceTreeBrowser extends ConsumerStatefulWidget {
  const WorkspaceTreeBrowser({
    super.key,
    required this.root,
    required this.onPickPath,
    this.onOpenFile,
    this.loading = false,
  });

  final RouteNode? root;
  final void Function(String contextRef) onPickPath;
  final void Function(String path)? onOpenFile;
  final bool loading;

  @override
  ConsumerState<WorkspaceTreeBrowser> createState() =>
      _WorkspaceTreeBrowserState();
}

class _WorkspaceTreeBrowserState extends ConsumerState<WorkspaceTreeBrowser> {
  String? _selectedPath;

  void _clearSelection() => setState(() => _selectedPath = null);

  void _selectPath(String path) {
    setState(() => _selectedPath = path);
    HapticFeedback.selectionClick();
  }

  void _confirmSelection() {
    final path = _selectedPath;
    if (path == null || path.isEmpty) {
      return;
    }
    widget.onPickPath('@$path');
    _clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final explorer = ref.watch(workspaceTreeExplorerProvider);

    if (widget.loading && widget.root == null) {
      return const SizedBox.shrink();
    }

    final root = widget.root;
    if (root == null) {
      return Center(
        child: Text(
          'No workspace tree loaded.',
          style: TextStyle(color: colors.fgMuted, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selectedPath != null)
          Container(
            height: 44,
            color: colors.app,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: _clearSelection,
                  icon: Icon(Icons.close, color: colors.fgMuted, size: 20),
                  tooltip: 'Cancel',
                ),
                Expanded(
                  child: Text(
                    _selectedPath!,
                    style: workbenchMonoStyle(context, size: 12),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
                IconButton(
                  onPressed: _confirmSelection,
                  icon: Icon(Icons.check, color: colors.accentPrimary, size: 20),
                  tooltip: 'Add to composer',
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final child in root.children)
                _TreeTile(
                  node: child,
                  depth: 0,
                  selectedPath: _selectedPath,
                  expandedPaths: explorer.expandedPaths,
                  onLongPress: _selectPath,
                  onOpenFile: widget.onOpenFile,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TreeTile extends ConsumerWidget {
  const _TreeTile({
    required this.node,
    required this.depth,
    required this.selectedPath,
    required this.expandedPaths,
    required this.onLongPress,
    this.onOpenFile,
  });

  final RouteNode node;
  final int depth;
  final String? selectedPath;
  final Set<String> expandedPaths;
  final ValueChanged<String> onLongPress;
  final void Function(String path)? onOpenFile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.workbenchColors;
    final selected = selectedPath == node.path;
    final isFolder = node.isFolder;
    final children = node.children;
    final hasChildren = children.isNotEmpty;
    final expanded = expandedPaths.contains(node.path);
    final explorer = ref.read(workspaceTreeExplorerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onLongPress: () => onLongPress(node.path),
          child: Material(
            color: selected
                ? colors.aiCommandBg.withValues(alpha: 0.35)
                : Colors.transparent,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.only(left: 8.0 + depth * 16),
              leading: Icon(
                isFolder
                    ? (expanded
                        ? Icons.folder_open_outlined
                        : Icons.folder_outlined)
                    : Icons.insert_drive_file_outlined,
                size: 18,
                color: isFolder ? colors.aiEditedFileFg : colors.fgMuted,
              ),
              title: Text(
                node.asset,
                style: workbenchMonoStyle(context, size: 13),
              ),
              subtitle: Text(
                node.path,
                style: TextStyle(color: colors.fgMuted, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: hasChildren
                  ? IconButton(
                      icon: Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: colors.fgMuted,
                      ),
                      onPressed: () => explorer.toggleExpanded(node.path),
                    )
                  : null,
              onTap: () {
                if (hasChildren) {
                  explorer.toggleExpanded(node.path);
                } else if (!isFolder) {
                  onOpenFile?.call(node.path);
                }
              },
            ),
          ),
        ),
        if (expanded)
          for (final child in children)
            _TreeTile(
              node: child,
              depth: depth + 1,
              selectedPath: selectedPath,
              expandedPaths: expandedPaths,
              onLongPress: onLongPress,
              onOpenFile: onOpenFile,
            ),
      ],
    );
  }
}
