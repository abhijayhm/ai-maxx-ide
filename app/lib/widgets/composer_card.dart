import 'package:flutter/material.dart';

import '../theme/workbench_colors.dart';

class ComposerCard extends StatelessWidget {
  const ComposerCard({
    super.key,
    required this.controller,
    required this.onSend,
    this.onStop,
    this.running = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.elevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(color: colors.fgDefault, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Plan, Build, / for skills, @ for context',
              hintStyle: TextStyle(color: colors.fgPlaceholder),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.input,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('∞', style: TextStyle(color: colors.fgMuted)),
              ),
              const SizedBox(width: 8),
              Text('Auto ⌄', style: TextStyle(color: colors.fgMuted, fontSize: 12)),
              const Spacer(),
              if (running && onStop != null)
                IconButton(
                  onPressed: onStop,
                  icon: Icon(Icons.stop, color: colors.statusError, size: 20),
                  tooltip: 'Stop agent',
                ),
              IconButton(
                onPressed: onSend,
                icon: Icon(Icons.send, color: colors.accentPrimary, size: 20),
                tooltip: 'Send',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
