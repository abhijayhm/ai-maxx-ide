import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/route_node.dart';
import '../../core/providers/projects_browse_provider.dart';
import '../../core/providers/agent_provider.dart';
import '../../core/providers/agent_session_provider.dart';
import '../../core/providers/ide_file_provider.dart';
import '../../core/providers/ide_index_provider.dart';
import '../../core/providers/ide_search_provider.dart';
import '../../theme/workbench_colors.dart';
import '../../theme/workbench_theme.dart';
import '../../widgets/agent_responses_panel.dart';
import '../../widgets/composer_card.dart';
import '../../widgets/segmented_toggle.dart';
import '../../widgets/workbench_search_field.dart';
import '../../widgets/workspace_file_viewer.dart';
import '../../widgets/workspace_tree_browser.dart';

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  final _searchController = TextEditingController();
  final _composerController = TextEditingController();
  String _debouncedQuery = '';
  Timer? _debounce;
  bool _agentExpanded = false;

  void _runFindSearchIfNeeded() {
    final browse = ref.read(projectsBrowseProvider);
    if (browse.searchMode != 1) {
      return;
    }
    final q = browse.query.trim();
    if (q.isEmpty) {
      ref.read(ideSearchProvider.notifier).search('');
      return;
    }
    ref.read(ideSearchProvider.notifier).search(q);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final browse = ref.read(projectsBrowseProvider);
      _searchController.text = browse.query;
      setState(() => _debouncedQuery = browse.query);
      _runFindSearchIfNeeded();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    ref.read(projectsBrowseProvider.notifier).setQuery(value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) {
        return;
      }
      setState(() => _debouncedQuery = value);
      final searchMode = ref.read(projectsBrowseProvider).searchMode;
      if (searchMode == 1 && value.trim().isNotEmpty) {
        ref.read(ideSearchProvider.notifier).search(value);
      }
    });
  }

  void _openFile(String path) {
    ref.read(ideFileProvider.notifier).open(path);
  }

  void _closeFile() {
    ref.read(ideFileProvider.notifier).close();
  }

  void _insertContextRef(String contextRef) {
    final current = _composerController.text;
    final next = current.trim().isEmpty ? contextRef : '$current\n$contextRef';
    _composerController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _sendComposer() {
    final text = _composerController.text.trim();
    if (text.isEmpty) {
      return;
    }
    ref.read(agentProvider.notifier).send(text);
    _composerController.clear();
  }

  void _toggleAgentExpanded() {
    setState(() => _agentExpanded = !_agentExpanded);
  }

  bool get _isSearching => ref.watch(projectsBrowseProvider).isSearching;

  Widget _buildAgentPanel({
    required AgentState agent,
    required AgentSessionsState agentSessions,
    required List<AgentEvent> activeMessages,
    required int? activeSessionId,
    required bool expanded,
  }) {
    return AgentResponsesPanel(
      messages: activeMessages,
      sessions: agentSessions.sessions,
      activeSessionId: activeSessionId,
      sessionsLoading: agentSessions.loading,
      running: agent.running && agent.runningSessionId == activeSessionId,
      expanded: expanded,
      onToggleExpanded: _toggleAgentExpanded,
      onSessionSelected: (id) =>
          ref.read(agentSessionsProvider.notifier).selectSession(id),
      onNewSession: () =>
          ref.read(agentSessionsProvider.notifier).createSession(select: true),
    );
  }

  Widget _buildComposer(AgentState agent) {
    return ComposerCard(
      controller: _composerController,
      running: agent.running,
      onSend: _sendComposer,
      onStop: agent.running
          ? () => ref.read(agentProvider.notifier).stop()
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final index = ref.watch(ideIndexProvider);
    final grep = ref.watch(ideSearchProvider);
    final agent = ref.watch(agentProvider);
    final agentSessions = ref.watch(agentSessionsProvider);
    final openFile = ref.watch(ideFileProvider);
    final activeSessionId = agentSessions.activeId;
    final activeMessages = agent.messagesFor(activeSessionId);

    final browse = ref.watch(projectsBrowseProvider);
    final query = browse.query;
    final searchMode = browse.searchMode;

    if (openFile.isOpen) {
      return ColoredBox(
        color: colors.canvas,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  WorkspaceFileViewer(
                    file: openFile,
                    onClose: _closeFile,
                    onPickRange: _insertContextRef,
                  ),
                  if (_agentExpanded)
                    Positioned.fill(
                      child: Material(
                        color: colors.canvas,
                        elevation: 2,
                        child: _buildAgentPanel(
                          agent: agent,
                          agentSessions: agentSessions,
                          activeMessages: activeMessages,
                          activeSessionId: activeSessionId,
                          expanded: true,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!_agentExpanded)
              _buildAgentPanel(
                agent: agent,
                agentSessions: agentSessions,
                activeMessages: activeMessages,
                activeSessionId: activeSessionId,
                expanded: false,
              ),
            _buildComposer(agent),
          ],
        ),
      );
    }

    final fileHits = searchMode == 0
        ? searchByName(index.searchable, _debouncedQuery)
        : <RouteNode>[];

    return ColoredBox(
      color: colors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: WorkbenchSearchField(
              controller: _searchController,
              hintText: searchMode == 0 ? 'Search files' : 'Grep pattern',
              onChanged: _onQueryChanged,
              onClear: () {
                _searchController.clear();
                ref.read(projectsBrowseProvider.notifier).clearQuery();
                ref.read(ideSearchProvider.notifier).search('');
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
                  options: const ['File Search', 'Find'],
                  selectedIndex: searchMode,
                  onChanged: (index) {
                    ref.read(projectsBrowseProvider.notifier).setSearchMode(index);
                    if (index == 1) {
                      _runFindSearchIfNeeded();
                    }
                  },
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    searchMode == 1 && grep.results.isNotEmpty
                        ? '${grep.results.length} matches'
                        : index.loading
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
            child: Stack(
              children: [
                Positioned.fill(
                  child: _isSearching
                      ? (searchMode == 0
                          ? _FileResultsList(
                              files: fileHits,
                              query: query,
                              onOpen: _openFile,
                            )
                          : _GrepResultsList(
                              grep: grep,
                              query: query,
                              onOpen: _openFile,
                            ))
                      : WorkspaceTreeBrowser(
                          root: index.workspaceTree,
                          loading: index.loading && index.workspaceTree == null,
                          onPickPath: _insertContextRef,
                          onOpenFile: _openFile,
                        ),
                ),
                if (_agentExpanded)
                  Positioned.fill(
                    child: Material(
                      color: colors.canvas,
                      elevation: 2,
                      child: _buildAgentPanel(
                        agent: agent,
                        agentSessions: agentSessions,
                        activeMessages: activeMessages,
                        activeSessionId: activeSessionId,
                        expanded: true,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!_agentExpanded)
            _buildAgentPanel(
              agent: agent,
              agentSessions: agentSessions,
              activeMessages: activeMessages,
              activeSessionId: activeSessionId,
              expanded: false,
            ),
          _buildComposer(agent),
        ],
      ),
    );
  }
}

class _FileResultsList extends StatelessWidget {
  const _FileResultsList({
    required this.files,
    required this.query,
    required this.onOpen,
  });

  final List<RouteNode> files;
  final String query;
  final void Function(String path) onOpen;

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
        return Material(
          color: Colors.transparent,
          child: ListTile(
            dense: true,
            onTap: () => onOpen(file.path),
            title: Text(file.asset, style: workbenchMonoStyle(context, size: 13)),
            subtitle: Text(
              file.path,
              style: TextStyle(color: colors.fgMuted, fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }
}

class _GrepResultsList extends StatelessWidget {
  const _GrepResultsList({
    required this.grep,
    required this.query,
    required this.onOpen,
  });

  final IdeSearchState grep;
  final String query;
  final void Function(String path) onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    if (grep.searching && grep.results.isEmpty) {
      return const SizedBox.shrink();
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
        return Material(
          color: Colors.transparent,
          child: ListTile(
            dense: true,
            onTap: () => onOpen(hit.path),
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
          ),
        );
      },
    );
  }
}
