import 'package:flutter/material.dart';

import '../../theme/workbench_colors.dart';

class TerminalsScreen extends StatelessWidget {
  const TerminalsScreen({super.key});

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
              color: colors.chrome,
              border: Border(bottom: BorderSide(color: colors.borderSubtle)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.statusSuccess,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text('terminal-1', style: TextStyle(color: colors.fgDefault)),
                const Spacer(),
                IconButton(
                  onPressed: () {},
                  icon: Icon(Icons.add, color: colors.fgMuted, size: 18),
                  tooltip: 'New terminal',
                ),
                IconButton(
                  onPressed: () {},
                  icon: Icon(Icons.delete_outline, color: colors.fgMuted, size: 18),
                  tooltip: 'Delete terminal',
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Terminal output stub — WebSocket /ws/terminals/{id}/.',
                style: TextStyle(color: colors.fgMuted, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
