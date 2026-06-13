import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_repository.dart';
import '../../core/providers/app_providers.dart';
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
  List<WorkspaceSummary> _workspaces = [];
  List<_TreeEntry> _treeEntries = [];
  String? _selectedPath;
  bool _loading = true;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider).valueOrNull;
    if (session == null || !session.isAuthenticated) {
      setState(() {
        _loading = false;
        _workspaces = [];
        _treeEntries = [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = await ref.read(authRepositoryProvider.future);
      final workspaces = await auth.listWorkspaces();
      final roots = await auth.listFileRoots();
      setState(() {
        _workspaces = workspaces;
        _treeEntries = roots
            .map(
              (root) => _TreeEntry(
                name: root.name.isEmpty ? root.fullPath : root.name,
                path: root.fullPath,
                isDirectory: true,
                depth: 0,
              ),
            )
            .toList();
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _expandDirectory(String path, int depth) async {
    try {
      final auth = await ref.read(authRepositoryProvider.future);
      final node = await auth.listByPath(path);
      final children = node.children
          .where((child) => child.type == 'directory')
          .map(
            (child) => _TreeEntry(
              name: child.name,
              path: child.path,
              isDirectory: true,
              depth: depth + 1,
            ),
          )
          .toList();

      setState(() {
        final index = _treeEntries.indexWhere((entry) => entry.path == path);
        if (index == -1) {
          return;
        }
        _treeEntries.removeWhere(
          (entry) => entry.depth > depth && _isDescendant(entry.path, path),
        );
        _treeEntries.insertAll(index + 1, children);
        _selectedPath = path;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load directory: $error')),
        );
      }
    }
  }

  bool _isDescendant(String candidate, String parent) {
    return candidate.startsWith('$parent/') || candidate.startsWith('$parent\\');
  }

  Future<void> _openWorkspace() async {
    final path = _selectedPath;
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a folder from exposed roots.')),
      );
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

  Future<void> _selectExistingWorkspace(WorkspaceSummary workspace) async {
    setState(() => _opening = true);
    try {
      await ref.read(sessionProvider.notifier).setWorkspace(workspace.id);
      if (mounted) {
        context.go('/projects');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to select workspace: $error')),
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
    ref.listen(sessionProvider, (previous, next) {
      final wasAuth = previous?.valueOrNull?.isAuthenticated ?? false;
      final isAuth = next.valueOrNull?.isAuthenticated ?? false;
      if (wasAuth != isAuth) {
        _load();
      }
    });

    final colors = context.workbenchColors;
    final session = ref.watch(sessionProvider).valueOrNull;
    final authenticated = session?.isAuthenticated ?? false;

    return Scaffold(
      backgroundColor: colors.app,
      body: SafeArea(
        child: Column(
          children: [
            _MenuHeader(
              activeTab: _MenuTab.workspace,
              onClose: () {
                final ready = session?.isReady ?? false;
                context.go(ready ? '/projects' : '/menu/workspace');
              },
            ),
            if (!authenticated)
              _AuthenticateBanner(
                onAuthenticate: () => showAuthModal(context, ref),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              _error!,
                              style: TextStyle(color: colors.statusError),
                            ),
                          ),
                        Text(
                          'Workspaces',
                          style: TextStyle(
                            color: colors.fgStrong,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_workspaces.isEmpty)
                          Text(
                            'No workspaces yet. Open one from exposed roots below.',
                            style: TextStyle(color: colors.fgMuted, fontSize: 13),
                          )
                        else
                          ..._workspaces.map(
                            (workspace) => ListTile(
                              dense: true,
                              title: Text(
                                workspace.label.isEmpty
                                    ? workspace.absolutePath
                                    : workspace.label,
                                style: workbenchMonoStyle(context),
                              ),
                              subtitle: Text(
                                workspace.absolutePath,
                                style: TextStyle(
                                  color: colors.fgMuted,
                                  fontSize: 12,
                                ),
                              ),
                              onTap: _opening
                                  ? null
                                  : () => _selectExistingWorkspace(workspace),
                            ),
                          ),
                        const SizedBox(height: 20),
                        Text(
                          'Exposed roots',
                          style: TextStyle(
                            color: colors.fgStrong,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._treeEntries.map(
                          (entry) => _TreeRow(
                            entry: entry,
                            selected: _selectedPath == entry.path,
                            onTap: () => _expandDirectory(entry.path, entry.depth),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          readOnly: true,
                          controller: TextEditingController(text: _selectedPath ?? ''),
                          decoration: const InputDecoration(
                            labelText: 'Selected path',
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: !authenticated || _opening ? null : _openWorkspace,
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

enum _MenuTab { workspace, git }

class _MenuHeader extends StatelessWidget {
  const _MenuHeader({
    required this.activeTab,
    required this.onClose,
  });

  final _MenuTab activeTab;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.chrome,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onClose,
                  icon: Icon(Icons.close, color: colors.fgDefault),
                  tooltip: 'Close menu',
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => context.go('/menu/git'),
                  icon: Icon(Icons.account_tree_outlined, color: colors.fgMuted),
                  tooltip: 'Git menu',
                ),
              ],
            ),
          ),
          Row(
            children: [
              _HeaderTab(
                label: 'Workspace',
                selected: activeTab == _MenuTab.workspace,
                onTap: () => context.go('/menu/workspace'),
              ),
              _HeaderTab(
                label: 'Git',
                selected: activeTab == _MenuTab.git,
                onTap: () => context.go('/menu/git'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderTab extends StatelessWidget {
  const _HeaderTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? colors.accentPrimary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colors.fgStrong : colors.fgMuted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthenticateBanner extends StatelessWidget {
  const _AuthenticateBanner({required this.onAuthenticate});

  final VoidCallback onAuthenticate;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return Container(
      width: double.infinity,
      color: colors.elevated,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Authenticate with the server API key to list workspaces.',
              style: TextStyle(color: colors.fgDefault, fontSize: 13),
            ),
          ),
          ElevatedButton(
            onPressed: onAuthenticate,
            child: const Text('Authenticate'),
          ),
        ],
      ),
    );
  }
}

class _TreeEntry {
  const _TreeEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.depth,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int depth;
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final _TreeEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return Material(
      color: selected ? colors.canvas : colors.chrome,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 32,
          child: Row(
            children: [
              SizedBox(width: 12.0 + entry.depth * 16),
              if (selected)
                Container(width: 3, height: 14, color: colors.accentPrimary),
              Icon(
                Icons.folder_outlined,
                size: 16,
                color: colors.aiEditedFileFg,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.name,
                  style: workbenchMonoStyle(context, size: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
