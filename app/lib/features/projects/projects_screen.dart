import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/route_node.dart';
import '../../core/providers/agent_provider.dart';
import '../../core/providers/ide_index_provider.dart';
import '../../core/providers/ide_search_provider.dart';
import '../../theme/workbench_colors.dart';
import '../../theme/workbench_theme.dart';
import '../../widgets/agent_responses_panel.dart';
import '../../widgets/composer_card.dart';
import '../../widgets/segmented_toggle.dart';
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
  int _searchMode = 0;

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
      if (!mounted) {
        return;
      }
      setState(() => _debouncedQuery = value);
      if (_searchMode == 1 && value.trim().isNotEmpty) {
        ref.read(ideSearchProvider.notifier).search(value);
      }
    });
  }

  bool get _isSearching => _query.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final index = ref.watch(ideIndexProvider);
    final grep = ref.watch(ideSearchProvider);
    final agent = ref.watch(agentProvider);

    final fileHits = _searchMode == 0
        ? searchByName(index.searchable, _debouncedQuery)
        : <RouteNode>[];

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
                  child: Text(
                    index.loading
                        ? 'Indexing…'
                        : '${index.searchable.length} indexed',
                    style: TextStyle(color: colors.fgMuted, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          if (index.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                index.error!,
                style: TextStyle(color: colors.statusError, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            flex: resultsFlex == 0 ? 1 : resultsFlex,
            child: _isSearching
                ? (_searchMode == 0
                    ? _FileResultsList(files: fileHits, query: _query)
                    : _GrepResultsList(grep: grep, query: _query))
                : Center(
                    child: Text(
                      index.loading
                          ? 'Loading workspace index…'
                          : 'Type to search indexed files by name.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.fgMuted, fontSize: 13),
                    ),
                  ),
          ),
          if (agentFlex > 0)
            Expanded(
              flex: agentFlex,
              child: Column(
                children: [
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
            onSend: () {},
            onStop: null,
          ),
        ],
      ),
    );
  }
}

class _FileResultsList extends StatelessWidget {
  const _FileResultsList({required this.files, required this.query});

  final List<RouteNode> files;
  final String query;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    if (files.isEmpty) {
      return Center(
        child: Text(
          'No files matched "$query".',
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
          title: Text(file.asset, style: workbenchMonoStyle(context, size: 13)),
          subtitle: Text(
            file.path,
            style: TextStyle(color: colors.fgMuted, fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

class _GrepResultsList extends StatelessWidget {
  const _GrepResultsList({required this.grep, required this.query});

  final IdeSearchState grep;
  final String query;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    if (grep.searching && grep.results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (grep.error != null) {
      return Center(
        child: Text(grep.error!, style: TextStyle(color: colors.statusError)),
      );
    }
    if (grep.results.isEmpty) {
      return Center(
        child: Text(
          'No grep matches for "$query".',
          style: TextStyle(color: colors.fgMuted, fontSize: 13),
        ),
      );
    }
    return ListView.separated(
      itemCount: grep.results.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: colors.borderSubtle),
      itemBuilder: (context, index) {
        final hit = grep.results[index];
        return ListTile(
          dense: true,
          title: Text(hit.asset, style: workbenchMonoStyle(context, size: 13)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hit.path,
                style: TextStyle(color: colors.fgMuted, fontSize: 11),
              ),
              Text(
                'L${hit.line}: ${hit.text}',
                style: workbenchMonoStyle(context, size: 11, color: colors.fgMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}
