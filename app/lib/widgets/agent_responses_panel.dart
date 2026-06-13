import 'package:flutter/material.dart';

import '../core/agent/agent_client.dart';
import '../theme/workbench_colors.dart';
import '../theme/workbench_theme.dart';

class AgentResponsesPanel extends StatelessWidget {
  const AgentResponsesPanel({
    super.key,
    required this.messages,
    this.running = false,
  });

  final List<AgentEvent> messages;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    if (messages.isEmpty && !running) {
      return Center(
        child: Text(
          'Agent responses appear here.',
          style: TextStyle(color: colors.fgMuted, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: messages.length + (running ? 1 : 0),
      itemBuilder: (context, index) {
        if (running && index == messages.length) {
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

        final event = messages[index];
        final text = event.text ?? event.raw.toString();
        final isCommand = event.type == AgentEventType.runStarted;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isCommand ? colors.aiCommandBg : colors.elevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Text(
            text,
            style: workbenchMonoStyle(
              context,
              size: 13,
              color: isCommand ? colors.aiCommandFg : colors.fgDefault,
            ),
          ),
        );
      },
    );
  }
}
