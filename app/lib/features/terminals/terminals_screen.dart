import 'package:flutter/material.dart';

import '../../theme/workbench_colors.dart';
import '../../theme/workbench_theme.dart';

/// UI-only placeholder until terminal WebSocket is reintroduced.
class TerminalsScreen extends StatefulWidget {
  const TerminalsScreen({super.key});

  @override
  State<TerminalsScreen> createState() => _TerminalsScreenState();
}

class _TerminalsScreenState extends State<TerminalsScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return ColoredBox(
      color: colors.canvas,
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.elevated,
              border: Border(bottom: BorderSide(color: colors.borderDefault)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.fgInactive,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Terminal (coming soon)',
                    style: TextStyle(color: colors.fgStrong, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                'Terminal output will appear here…',
                style: workbenchMonoStyle(context, size: 13, color: colors.fgMuted),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: colors.elevated,
              border: Border(top: BorderSide(color: colors.borderSubtle)),
            ),
            child: TextField(
              controller: _inputController,
              enabled: false,
              style: workbenchMonoStyle(context, size: 13),
              decoration: const InputDecoration(
                hintText: 'Terminals not connected in this build',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
