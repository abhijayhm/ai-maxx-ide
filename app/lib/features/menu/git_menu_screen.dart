import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/workbench_colors.dart';

class GitMenuScreen extends StatelessWidget {
  const GitMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return Scaffold(
      backgroundColor: colors.app,
      body: SafeArea(
        child: Column(
          children: [
            _GitMenuHeader(onClose: () => context.go('/projects')),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Git operations stub — commit, stage, branch, and history will wire to /api/git/* routes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.fgMuted, fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GitMenuHeader extends StatelessWidget {
  const _GitMenuHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.chrome,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onClose,
                  icon: Icon(Icons.close, color: colors.fgDefault),
                  tooltip: 'Close menu',
                ),
                const Spacer(),
              ],
            ),
          ),
          Row(
            children: [
              _HeaderTab(
                label: 'Workspace',
                selected: false,
                onTap: () => context.go('/menu/workspace'),
              ),
              _HeaderTab(
                label: 'Git',
                selected: true,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderTab extends StatelessWidget {
  const _HeaderTab({
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

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? colors.accentPrimary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colors.fgStrong : colors.fgMuted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
