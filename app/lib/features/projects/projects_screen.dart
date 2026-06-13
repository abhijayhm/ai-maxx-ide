import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/file_search_provider.dart';
import '../../core/providers/sync_provider.dart';
import '../../theme/workbench_colors.dart';
import '../../theme/workbench_theme.dart';
import '../../widgets/workbench_search_field.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final sync = ref.watch(workspaceSyncProvider);
    final stats = ref.watch(indexedFileStatsProvider);
    final results = ref.watch(fileSearchProvider(_query));

    return ColoredBox(
      color: colors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: WorkbenchSearchField(
              controller: _searchController,
              hintText: 'Search files',
              onChanged: _onQueryChanged,
              onClear: () {
                _searchController.clear();
                _onQueryChanged('');
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _ModeChip(label: 'File search', selected: true, onTap: () {}),
                const SizedBox(width: 8),
                _ModeChip(label: 'grep', selected: false, onTap: () {}),
                const Spacer(),
                stats.when(
                  data: (value) => Text(
                    sync.isActive
                        ? sync.statusLabel
                        : '${value.total} files indexed',
                    style: TextStyle(color: colors.fgMuted, fontSize: 11),
                  ),
                  loading: () => Text(
                    sync.statusLabel,
                    style: TextStyle(color: colors.fgMuted, fontSize: 11),
                  ),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _query.trim().isEmpty
                ? Center(
                    child: Text(
                      sync.isActive
                          ? 'Workspace is indexing in the background.\nYou can keep using the app.'
                          : 'Type to search the synced workspace index.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.fgMuted, fontSize: 13),
                    ),
                  )
                : results.when(
                    data: (files) {
                      if (files.isEmpty) {
                        return Center(
                          child: Text(
                            sync.isActive
                                ? 'No matches yet. Indexing may still be running.'
                                : 'No files matched "$_query".',
                            style:
                                TextStyle(color: colors.fgMuted, fontSize: 13),
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: files.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: colors.borderSubtle,
                        ),
                        itemBuilder: (context, index) {
                          final file = files[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              file.name,
                              style: workbenchMonoStyle(context, size: 13),
                            ),
                            subtitle: Text(
                              file.path,
                              style: TextStyle(
                                color: colors.fgMuted,
                                fontSize: 11,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: file.hasContent
                                ? Icon(
                                    Icons.check_circle_outline,
                                    size: 16,
                                    color: colors.statusSuccess,
                                  )
                                : Icon(
                                    Icons.description_outlined,
                                    size: 16,
                                    color: colors.fgInactive,
                                  ),
                          );
                        },
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => Center(
                      child: Text(
                        'Search failed: $error',
                        style: TextStyle(color: colors.statusError),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.accentPrimary : colors.input,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? colors.accentPrimary : colors.borderDefault,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.fgStrong : colors.fgDefault,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
