import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/git_provider.dart';
import '../../core/repositories/git_repository.dart';
import '../../theme/workbench_colors.dart';
import '../../theme/workbench_theme.dart';

class GitMenuScreen extends ConsumerStatefulWidget {
  const GitMenuScreen({super.key});

  @override
  ConsumerState<GitMenuScreen> createState() => _GitMenuScreenState();
}

class _GitMenuScreenState extends ConsumerState<GitMenuScreen> {
  final _commitController = TextEditingController();
  final _commandController = TextEditingController();
  String? _selectedBranch;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(gitProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _commitController.dispose();
    _commandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final git = ref.watch(gitProvider);

    ref.listen(gitProvider, (previous, next) {
      if (_selectedBranch == null && next.currentBranch != null) {
        setState(() => _selectedBranch = next.currentBranch);
      }
    });

    return Scaffold(
      backgroundColor: colors.app,
      body: SafeArea(
        child: Column(
          children: [
            _GitMenuHeader(onClose: () => context.go('/projects')),
            if (git.loading)
              LinearProgressIndicator(
                minHeight: 2,
                color: colors.accentPrimary,
                backgroundColor: colors.borderSubtle,
              ),
            if (git.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  git.error!,
                  style: TextStyle(color: colors.statusError, fontSize: 12),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commitController,
                          decoration: const InputDecoration(
                            hintText: 'Commit message',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: git.loading
                            ? null
                            : () async {
                                final message = _commitController.text.trim();
                                if (message.isEmpty) {
                                  return;
                                }
                                await ref
                                    .read(gitProvider.notifier)
                                    .commit(message);
                                _commitController.clear();
                              },
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Commit'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _QuickAction(
                        label: 'Add',
                        onTap: () async {
                          for (final file in git.files) {
                            await ref.read(gitProvider.notifier).stage(file.path);
                          }
                        },
                      ),
                      _QuickAction(
                        label: 'Stash',
                        onTap: () => ref.read(gitProvider.notifier).stash(),
                      ),
                      _QuickAction(
                        label: 'Discard',
                        destructive: true,
                        onTap: () async {
                          for (final file in List.of(git.files)) {
                            await ref
                                .read(gitProvider.notifier)
                                .discard(file.path);
                          }
                        },
                      ),
                      _QuickAction(
                        label: 'Sync',
                        onTap: () => ref.read(gitProvider.notifier).sync(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Changed files',
                    style: TextStyle(
                      color: colors.fgStrong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (git.files.isEmpty)
                    Text(
                      'No changes',
                      style: TextStyle(color: colors.fgMuted, fontSize: 13),
                    )
                  else
                    ...git.files.map(
                      (file) => _ChangedFileRow(
                        file: file,
                        onStage: () =>
                            ref.read(gitProvider.notifier).stage(file.path),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _commandController,
                    style: workbenchMonoStyle(context, size: 13),
                    decoration: InputDecoration(
                      hintText: 'git command…',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.keyboard_return),
                        onPressed: () async {
                          final cmd = _commandController.text.trim();
                          if (cmd.isEmpty) {
                            return;
                          }
                          await ref.read(gitProvider.notifier).exec(cmd);
                        },
                      ),
                    ),
                    onSubmitted: (value) async {
                      if (value.trim().isEmpty) {
                        return;
                      }
                      await ref.read(gitProvider.notifier).exec(value.trim());
                    },
                  ),
                  if (git.lastOutput != null && git.lastOutput!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(
                        git.lastOutput!,
                        style: workbenchMonoStyle(context,
                            size: 11, color: colors.fgMuted),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedBranch ?? git.currentBranch,
                          decoration: const InputDecoration(
                            labelText: 'Branch',
                            isDense: true,
                          ),
                          items: git.branches
                              .map(
                                (branch) => DropdownMenuItem(
                                  value: branch,
                                  child: Text(
                                    branch,
                                    style: workbenchMonoStyle(context, size: 12),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _selectedBranch = value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _selectedBranch == null
                            ? null
                            : () => ref
                                .read(gitProvider.notifier)
                                .checkout(_selectedBranch!),
                        child: const Text('Select'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Commit history',
                    style: TextStyle(
                      color: colors.fgStrong,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...git.commits.map(
                    (commit) => _CommitRow(commit: commit),
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

class _ChangedFileRow extends StatelessWidget {
  const _ChangedFileRow({required this.file, required this.onStage});

  final GitChangedFile file;
  final VoidCallback onStage;

  Color _statusColor(WorkbenchColors colors) {
    switch (file.status.toUpperCase()) {
      case 'A':
        return colors.statusSuccess;
      case 'D':
        return colors.statusError;
      default:
        return colors.aiEditedFileFg;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return ListTile(
      dense: true,
      leading: Text(
        file.status,
        style: TextStyle(
          color: _statusColor(colors),
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
      title: Text(
        file.path,
        style: workbenchMonoStyle(context, size: 12),
      ),
      trailing: IconButton(
        onPressed: onStage,
        icon: Icon(Icons.add, color: colors.fgMuted, size: 18),
        tooltip: 'Stage file',
      ),
    );
  }
}

class _CommitRow extends StatelessWidget {
  const _CommitRow({required this.commit});

  final GitCommit commit;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4, right: 12),
            decoration: BoxDecoration(
              color: colors.accentPrimary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  commit.subject,
                  style: TextStyle(color: colors.fgDefault, fontSize: 13),
                ),
                Text(
                  '${commit.hash.substring(0, 7)} · ${commit.author} · ${commit.date}',
                  style: TextStyle(color: colors.fgInactive, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: destructive ? colors.statusError : colors.fgDefault,
        backgroundColor: colors.input,
      ),
      child: Text(label),
    );
  }
}

class _GitMenuHeader extends StatelessWidget {
  const _GitMenuHeader({required this.onClose});

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
              ],
            ),
          ),
          Row(
            children: [
              _HeaderTab(
                label: 'Workspace',
                selected: false,
                onTap: () => context.go('/menu/workspace'),
              ),
              _HeaderTab(
                label: 'Git',
                selected: true,
                onTap: () {},
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
