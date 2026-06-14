import 'package:flutter/material.dart';

import '../theme/workbench_colors.dart';

class WorkbenchLoaderOverlay extends StatelessWidget {
  const WorkbenchLoaderOverlay({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: colors.app.withValues(alpha: 0.72),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: colors.accentPrimary),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: TextStyle(
                    color: colors.fgDefault,
                    fontSize: 14,
                    decoration: TextDecoration.none,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
