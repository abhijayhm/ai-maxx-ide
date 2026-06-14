import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../core/models/agent_session.dart';
import '../core/providers/agent_provider.dart';
import '../theme/workbench_colors.dart';
import '../theme/workbench_theme.dart';

class AgentResponsesPanel extends StatefulWidget {
  const AgentResponsesPanel({
    super.key,
    required this.messages,
    required this.sessions,
    required this.activeSessionId,
    required this.onSessionSelected,
    required this.onNewSession,
    this.sessionsLoading = false,
    this.running = false,
    this.expanded = true,
    this.onToggleExpanded,
  });

  final List<AgentEvent> messages;
  final List<AgentSessionInfo> sessions;
  final int? activeSessionId;
  final ValueChanged<int> onSessionSelected;
  final VoidCallback onNewSession;
  final bool sessionsLoading;
  final bool running;
  final bool expanded;
  final VoidCallback? onToggleExpanded;

  @override
  State<AgentResponsesPanel> createState() => _AgentResponsesPanelState();
}

class _AgentResponsesPanelState extends State<AgentResponsesPanel> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AgentResponsesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeSessionId != oldWidget.activeSessionId && widget.expanded) {
      _scrollToEnd();
    }
    if (widget.messages.length != oldWidget.messages.length || widget.running) {
      if (widget.expanded) {
        _scrollToEnd();
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  AgentSessionInfo? get _activeSession {
    final id = widget.activeSessionId;
    if (id == null) {
      return null;
    }
    for (final session in widget.sessions) {
      if (session.id == id) {
        return session;
      }
    }
    return null;
  }

  Future<void> _openSessionPicker() async {
    final colors = context.workbenchColors;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.elevated,
      isScrollControlled: true,
      builder: (ctx) => _SessionPickerSheet(
        sessions: widget.sessions,
        activeSessionId: widget.activeSessionId,
        onSessionSelected: widget.onSessionSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final items = _groupMessages(widget.messages);
    final activeLabel = _activeSession?.label ?? 'Select session';

    return Column(
      mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
          child: Row(
            children: [
              if (widget.onToggleExpanded != null)
                IconButton(
                  onPressed: widget.onToggleExpanded,
                  icon: Icon(
                    widget.expanded
                        ? Icons.expand_more
                        : Icons.expand_less,
                    color: colors.fgMuted,
                    size: 20,
                  ),
                  tooltip: widget.expanded ? 'Collapse agent' : 'Expand agent',
                ),
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      widget.sessions.isEmpty ? null : _openSessionPicker,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    side: BorderSide(color: colors.borderSubtle),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.sessionsLoading
                          ? 'Loading sessions…'
                          : activeLabel,
                      style: workbenchMonoStyle(context, size: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              if (widget.running) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.accentPrimary,
                  ),
                ),
              ],
              IconButton(
                onPressed: widget.onNewSession,
                icon: Icon(Icons.add, color: colors.accentPrimary, size: 20),
                tooltip: 'New session',
              ),
            ],
          ),
        ),
        if (widget.expanded)
          Expanded(
            child: _buildMessageList(context, colors, items),
          ),
      ],
    );
  }

  Widget _buildMessageList(
    BuildContext context,
    WorkbenchColors colors,
    List<_DisplayMessage> items,
  ) {
    if (items.isEmpty && !widget.running) {
      return Center(
        child: Text(
          'Agent responses appear here.',
          style: TextStyle(color: colors.fgMuted, fontSize: 13),
        ),
      );
    }

    final markdownConfig = MarkdownConfig.darkConfig.copy(
      configs: [
        PreConfig.darkConfig.copy(theme: atomOneDarkTheme),
        PConfig(textStyle: TextStyle(fontSize: 14, color: colors.fgDefault)),
      ],
    );

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: items.length + (widget.running ? 1 : 0),
      itemBuilder: (context, index) {
        if (widget.running && index == items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.accentPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Agent running…',
                  style: TextStyle(color: colors.fgMuted, fontSize: 12),
                ),
              ],
            ),
          );
        }

        final item = items[index];
        if (item.text.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: item.isUser ? colors.aiCommandBg : colors.elevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: item.isError ? colors.statusError : colors.borderSubtle,
            ),
          ),
          child: item.isUser
              ? Text(
                  item.text,
                  style: workbenchMonoStyle(
                    context,
                    size: 13,
                    color: colors.aiCommandFg,
                  ),
                )
              : item.isError
                  ? Text(
                      item.text,
                      style: workbenchMonoStyle(
                        context,
                        size: 13,
                        color: colors.statusError,
                      ),
                    )
                  : MarkdownBlock(
                      data: item.text,
                      config: markdownConfig,
                    ),
        );
      },
    );
  }
}

class _DisplayMessage {
  const _DisplayMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
  });

  final String text;
  final bool isUser;
  final bool isError;

  bool get isAgent => !isUser && !isError;
}

List<_DisplayMessage> _groupMessages(List<AgentEvent> messages) {
  final items = <_DisplayMessage>[];

  for (final event in messages) {
    final text = event.text ?? '';
    final isUser =
        event.type == AgentEventType.stream && event.raw.isEmpty;

    if (isUser) {
      if (text.isNotEmpty) {
        items.add(_DisplayMessage(text: text, isUser: true));
      }
      continue;
    }

    if (event.type == AgentEventType.stream) {
      if (text.isEmpty) {
        continue;
      }
      if (!_isAssistantStream(event)) {
        continue;
      }
      if (items.isNotEmpty && items.last.isAgent) {
        final last = items.removeLast();
        items.add(_DisplayMessage(text: last.text + text, isUser: false));
      } else {
        items.add(_DisplayMessage(text: text, isUser: false));
      }
      continue;
    }

    if (event.type == AgentEventType.error && text.isNotEmpty) {
      items.add(_DisplayMessage(text: text, isUser: false, isError: true));
    }
  }

  return items;
}

bool _isAssistantStream(AgentEvent event) {
  if (event.raw.isEmpty) {
    return true;
  }
  final message = event.raw['message'];
  if (message is! Map<String, dynamic>) {
    return false;
  }
  return message['type'] == 'assistant';
}

class _SessionPickerSheet extends StatefulWidget {
  const _SessionPickerSheet({
    required this.sessions,
    required this.activeSessionId,
    required this.onSessionSelected,
  });

  final List<AgentSessionInfo> sessions;
  final int? activeSessionId;
  final ValueChanged<int> onSessionSelected;

  @override
  State<_SessionPickerSheet> createState() => _SessionPickerSheetState();
}

class _SessionPickerSheetState extends State<_SessionPickerSheet> {
  late final TextEditingController _queryController;
  late List<AgentSessionInfo> _filtered;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _filtered = widget.sessions;
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _filter(String value) {
    final q = value.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.sessions
          : widget.sessions
              .where((s) => s.label.toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _queryController,
              autofocus: true,
              style: TextStyle(color: colors.fgDefault, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search sessions',
                hintStyle: TextStyle(color: colors.fgPlaceholder),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onChanged: _filter,
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _filtered.length,
              itemBuilder: (ctx, i) {
                final session = _filtered[i];
                final selected = session.id == widget.activeSessionId;
                return ListTile(
                  dense: true,
                  selected: selected,
                  title: Text(
                    session.label,
                    style: workbenchMonoStyle(ctx, size: 13),
                  ),
                  subtitle: Text(
                    'Session #${session.id}',
                    style: TextStyle(
                      color: colors.fgMuted,
                      fontSize: 11,
                    ),
                  ),
                  onTap: () {
                    widget.onSessionSelected(session.id);
                    Navigator.pop(ctx);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
