import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models/route_node.dart';
import '../theme/workbench_colors.dart';
import '../theme/workbench_theme.dart';

/// Workspace file/folder tree with long-press path selection for agent context.
class WorkspaceTreeBrowser extends StatefulWidget {
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
  State<WorkspaceTreeBrowser> createState() => _WorkspaceTreeBrowserState();
}

class _WorkspaceTreeBrowserState extends State<WorkspaceTreeBrowser> {
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

    if (widget.loading && widget.root == null) {
      return const Center(child: CircularProgressIndicator());
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
              if (root.children.isEmpty)
                _TreeTile(
                  node: root,
                  depth: 0,
                  selectedPath: _selectedPath,
                  onLongPress: _selectPath,
                  onOpenFile: widget.onOpenFile,
                )
              else
                for (final child in root.children)
                  _TreeTile(
                    node: child,
                    depth: 0,
                    selectedPath: _selectedPath,
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

class _TreeTile extends StatefulWidget {
  const _TreeTile({
    required this.node,
    required this.depth,
    required this.selectedPath,
    required this.onLongPress,
    this.onOpenFile,
  });

  final RouteNode node;
  final int depth;
  final String? selectedPath;
  final ValueChanged<String> onLongPress;
  final void Function(String path)? onOpenFile;

  @override
  State<_TreeTile> createState() => _TreeTileState();
}

class _TreeTileState extends State<_TreeTile> {
  bool _expanded = false;

  List<RouteNode> get _children => widget.node.children;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final selected = widget.selectedPath == widget.node.path;
    final isFolder = widget.node.isFolder;
    final hasChildren = _children.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onLongPress: () => widget.onLongPress(widget.node.path),
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.only(left: 8.0 + widget.depth * 16),
            leading: Icon(
              isFolder
                  ? (_expanded
                      ? Icons.folder_open_outlined
                      : Icons.folder_outlined)
                  : Icons.insert_drive_file_outlined,
              size: 18,
              color: isFolder ? colors.aiEditedFileFg : colors.fgMuted,
            ),
            title: Text(
              widget.node.asset,
              style: workbenchMonoStyle(context, size: 13),
            ),
            subtitle: Text(
              widget.node.path,
              style: TextStyle(color: colors.fgMuted, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: hasChildren
                ? IconButton(
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: colors.fgMuted,
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                  )
                : null,
            selected: selected,
            selectedTileColor: colors.aiCommandBg.withValues(alpha: 0.35),
            onTap: () {
              if (hasChildren) {
                setState(() => _expanded = !_expanded);
              } else if (!isFolder) {
                widget.onOpenFile?.call(widget.node.path);
              }
            },
          ),
        ),
        if (_expanded)
          for (final child in _children)
            _TreeTile(
              node: child,
              depth: widget.depth + 1,
              selectedPath: widget.selectedPath,
              onLongPress: widget.onLongPress,
              onOpenFile: widget.onOpenFile,
            ),
      ],
    );
  }
}
