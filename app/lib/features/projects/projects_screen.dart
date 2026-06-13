import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/agent_provider.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/file_search_provider.dart';
import '../../core/providers/search_provider.dart';
import '../../core/repositories/search_repository.dart';
import '../../core/providers/sync_provider.dart';
import '../../core/sync/sync_models.dart';
import '../../theme/workbench_colors.dart';
import '../../theme/workbench_theme.dart';
import '../../widgets/agent_responses_panel.dart';
import '../../widgets/composer_card.dart';
import '../../widgets/segmented_toggle.dart';
import '../../widgets/sync_progress_banner.dart';
import '../../widgets/workbench_search_field.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  final _searchController = TextEditingController();
  final _composerController = TextEditingController();
  String _query = '';
  String _debouncedQuery = '';
  Timer? _debounce;
  int _searchMode = 0; // 0 = file, 1 = grep

  @override
  void initState() {
    super.initState();
    Future.microtask(_connectAgentWhenReady);
  }

  void _connectAgentWhenReady() {
    final session = ref.read(sessionProvider).valueOrNull;
    final sync = ref.read(workspaceSyncProvider);
    if ((session?.isReady ?? false) && !sync.isActive) {
      ref.read(agentProvider.notifier).connect();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() => _debouncedQuery = value);
      }
    });
  }

  bool get _isSearching => _query.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final sync = ref.watch(workspaceSyncProvider);
    final stats = ref.watch(indexedFileStatsProvider);
    final agent = ref.watch(agentProvider);

    ref.listen(sessionProvider, (previous, next) {
      final wasReady = previous?.valueOrNull?.isReady ?? false;
      final isReady = next.valueOrNull?.isReady ?? false;
      if (!wasReady && isReady && !sync.isActive) {
        ref.read(agentProvider.notifier).connect();
      }
    });

    ref.listen(workspaceSyncProvider, (previous, next) {
      final wasActive = previous?.isActive ?? false;
      if (wasActive && !next.isActive) {
        ref.read(agentProvider.notifier).connect();
      }
    });

    final fileResults = _searchMode == 0
        ? ref.watch(fileSearchProvider(_debouncedQuery))
        : const AsyncValue<List<IndexedFileRow>>.data([]);
    final grepResults = _searchMode == 1
        ? ref.watch(grepSearchProvider(_debouncedQuery))
        : const AsyncValue<List<GrepHit>>.data([]);

    final resultsFlex = _isSearching ? 3 : 2;
    final agentFlex = _isSearching ? 0 : 3;

    return ColoredBox(
      color: colors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: WorkbenchSearchField(
              controller: _searchController,
              hintText: _searchMode == 0 ? 'Search files' : 'Grep pattern',
              onChanged: _onQueryChanged,
              onClear: () {
                _searchController.clear();
                _onQueryChanged('');
              },
              onStop: agent.running
                  ? () => ref.read(agentProvider.notifier).stop()
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedToggle(
                  options: const ['File search', 'grep'],
                  selectedIndex: _searchMode,
                  onChanged: (index) => setState(() => _searchMode = index),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: stats.when(
                    data: (value) => Text(
                      sync.hasError
                          ? sync.statusLabel
                          : sync.isActive
                              ? sync.statusLabel
                              : '${value.total} indexed',
                      style: TextStyle(color: colors.fgMuted, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    loading: () => Text(
                      sync.statusLabel,
                      style: TextStyle(color: colors.fgMuted, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (sync.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SyncProgressBanner(progress: sync),
            ),
          Expanded(
            flex: resultsFlex == 0 ? 1 : resultsFlex,
            child: _isSearching
                ? (_searchMode == 0
                    ? _FileResultsList(
                        results: fileResults,
                        query: _query,
                        syncActive: sync.isActive,
                      )
                    : _GrepResultsList(
                        results: grepResults,
                        query: _query,
                      ))
                : (sync.isActive
                    ? SyncProgressPanel(progress: sync)
                    : sync.hasError
                        ? Center(
                            child: Text(
                              sync.errorMessage ?? 'Workspace sync failed',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colors.statusError,
                                fontSize: 13,
                              ),
                            ),
                          )
                        : Center(
                        child: Text(
                          'Type to search the synced workspace index.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.fgMuted, fontSize: 13),
                        ),
                      )),
          ),
          if (agentFlex > 0)
            Expanded(
              flex: agentFlex,
              child: Column(
                children: [
                  if (agent.error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: colors.statusError,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              agent.error!,
                              style: TextStyle(
                                color: colors.statusError,
                                fontSize: 12,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: AgentResponsesPanel(
                      messages: agent.messages,
                      running: agent.running,
                    ),
                  ),
                ],
              ),
            ),
          ComposerCard(
            controller: _composerController,
            running: agent.running,
            onSend: () {
              final text = _composerController.text.trim();
              if (text.isEmpty) {
                return;
              }
              ref.read(agentProvider.notifier).send(text);
              _composerController.clear();
            },
            onStop: agent.running
                ? () => ref.read(agentProvider.notifier).stop()
                : null,
          ),
        ],
      ),
    );
  }
}

class _FileResultsList extends StatelessWidget {
  const _FileResultsList({
    required this.results,
    required this.query,
    required this.syncActive,
  });

  final AsyncValue<List<IndexedFileRow>> results;
  final String query;
  final bool syncActive;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return results.when(
      data: (files) {
        if (files.isEmpty) {
          return Center(
            child: Text(
              syncActive
                  ? 'No matches yet. Indexing may still be running.'
                  : 'No files matched "$query".',
              style: TextStyle(color: colors.fgMuted, fontSize: 13),
            ),
          );
        }

        return ListView.separated(
          itemCount: files.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: colors.borderSubtle),
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
                style: TextStyle(color: colors.fgMuted, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: file.hasContent
                  ? Icon(Icons.check_circle_outline,
                      size: 16, color: colors.statusSuccess)
                  : Icon(Icons.description_outlined,
                      size: 16, color: colors.fgInactive),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text(
          'Search failed: $error',
          style: TextStyle(color: colors.statusError),
        ),
      ),
    );
  }
}

class _GrepResultsList extends StatelessWidget {
  const _GrepResultsList({
    required this.results,
    required this.query,
  });

  final AsyncValue<List<GrepHit>> results;
  final String query;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return results.when(
      data: (hits) {
        if (hits.isEmpty) {
          return Center(
            child: Text(
              'No grep matches for "$query".',
              style: TextStyle(color: colors.fgMuted, fontSize: 13),
            ),
          );
        }

        return ListView.separated(
          itemCount: hits.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: colors.borderSubtle),
          itemBuilder: (context, index) {
            final hit = hits[index];
            return ListTile(
              dense: true,
              title: Text(
                hit.path,
                style: workbenchMonoStyle(context, size: 13),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'L${hit.lineStart}-${hit.lineEnd}',
                    style: TextStyle(color: colors.fgInactive, fontSize: 11),
                  ),
                  for (final match in hit.matches.take(3))
                    Text(
                      '${match.line}: ${match.text}',
                      style: workbenchMonoStyle(context,
                          size: 11, color: colors.fgMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text(
          'Grep failed: $error',
          style: TextStyle(color: colors.statusError),
        ),
      ),
    );
  }
}
