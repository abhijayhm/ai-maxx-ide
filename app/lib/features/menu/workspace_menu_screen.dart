import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../core/models/route_node.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/ide_index_provider.dart';
import '../../theme/workbench_colors.dart';
import '../../theme/workbench_theme.dart';
import '../onboarding/auth_modal.dart';

class WorkspaceMenuScreen extends ConsumerStatefulWidget {
  const WorkspaceMenuScreen({super.key});

  @override
  ConsumerState<WorkspaceMenuScreen> createState() =>
      _WorkspaceMenuScreenState();
}

class _WorkspaceMenuScreenState extends ConsumerState<WorkspaceMenuScreen> {
  String? _selectedPath;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_restoreSelection);
  }

  Future<void> _restoreSelection() async {
    final db = await ref.read(appDatabaseProvider.future);
    final saved = await db.getSetting(AppDatabase.lastWorkspacePathKey);
    final session = ref.read(sessionProvider).valueOrNull;
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedPath = saved?.isNotEmpty == true
          ? saved
          : session?.isReady == true
              ? null
              : _selectedPath;
    });
  }

  Future<void> _openSelected() async {
    final path = _selectedPath;
    if (path == null || path.isEmpty) {
      return;
    }
    setState(() => _opening = true);
    try {
      await ref.read(sessionProvider.notifier).openWorkspace(path);
      if (mounted) {
        context.go('/projects');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open workspace: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final session = ref.watch(sessionProvider).valueOrNull;
    final index = ref.watch(ideIndexProvider);
    final authenticated = session?.isAuthenticated ?? false;

    return Scaffold(
      backgroundColor: colors.app,
      body: SafeArea(
        child: Column(
          children: [
            _MenuHeader(onClose: () => context.go('/projects')),
            if (!authenticated)
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () => showAuthModal(context, ref),
                  child: const Text('Authenticate'),
                ),
              ),
            if (index.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  index.error!,
                  style: TextStyle(color: colors.statusError, fontSize: 12),
                ),
              ),
            if (index.refreshing)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Refreshing…',
                    style: TextStyle(color: colors.fgMuted, fontSize: 11),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  index.loadedFromCache && index.hasData
                      ? 'Showing cached tree — refreshing in background'
                      : index.hasData
                          ? '${index.exposedFlat.length} exposed paths'
                          : 'Loading exposed paths…',
                  style: TextStyle(color: colors.fgMuted, fontSize: 11),
                ),
              ),
            ),
            Expanded(
              child: index.loading && !index.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : index.exposedTree.isEmpty
                      ? Center(
                          child: Text(
                            authenticated
                                ? 'No exposed folders found on server.'
                                : 'Authenticate to load folders.',
                            style: TextStyle(color: colors.fgMuted),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(8),
                          children: [
                            for (final root in index.exposedTree)
                              _RouteTreeTile(
                                node: root,
                                depth: 0,
                                selectedPath: _selectedPath,
                                onSelect: (path) =>
                                    setState(() => _selectedPath = path),
                              ),
                          ],
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedPath ?? 'Select a folder',
                      style: workbenchMonoStyle(context, size: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _opening || _selectedPath == null
                        ? null
                        : _openSelected,
                    child: _opening
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Open workspace'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteTreeTile extends StatefulWidget {
  const _RouteTreeTile({
    required this.node,
    required this.depth,
    required this.selectedPath,
    required this.onSelect,
  });

  final RouteNode node;
  final int depth;
  final String? selectedPath;
  final ValueChanged<String> onSelect;

  @override
  State<_RouteTreeTile> createState() => _RouteTreeTileState();
}

class _RouteTreeTileState extends State<_RouteTreeTile> {
  bool _expanded = false;

  List<RouteNode> get _folderChildren =>
      widget.node.children.where((c) => c.isFolder).toList();

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final selected = widget.selectedPath == widget.node.path;
    final hasChildren = _folderChildren.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(left: 8.0 + widget.depth * 16),
          leading: Icon(
            hasChildren
                ? (_expanded
                    ? Icons.folder_open_outlined
                    : Icons.folder_outlined)
                : Icons.folder_outlined,
            size: 18,
            color: colors.aiEditedFileFg,
          ),
          title: Text(
            widget.node.asset,
            style: workbenchMonoStyle(context, size: 13),
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
          onTap: () => widget.onSelect(widget.node.path),
        ),
        if (_expanded)
          for (final child in _folderChildren)
            _RouteTreeTile(
              node: child,
              depth: widget.depth + 1,
              selectedPath: widget.selectedPath,
              onSelect: widget.onSelect,
            ),
      ],
    );
  }
}

class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Workspace',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close, color: colors.fgMuted),
          ),
        ],
      ),
    );
  }
}
