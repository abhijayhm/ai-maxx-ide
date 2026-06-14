import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../core/providers/agent_provider.dart';
import '../theme/workbench_colors.dart';
import '../theme/workbench_theme.dart';

class AgentResponsesPanel extends StatefulWidget {
  const AgentResponsesPanel({
    super.key,
    required this.messages,
    this.running = false,
  });

  final List<AgentEvent> messages;
  final bool running;

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
    if (widget.messages.length != oldWidget.messages.length || widget.running) {
      _scrollToEnd();
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

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final items = _groupMessages(widget.messages);

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
      padding: const EdgeInsets.all(12),
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
            color: item.isUser
                ? colors.aiCommandBg
                : item.isError
                    ? colors.elevated
                    : colors.elevated,
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
