import 'package:flutter/material.dart';

import '../theme/workbench_colors.dart';

class WorkbenchSearchField extends StatelessWidget {
  const WorkbenchSearchField({
    super.key,
    this.controller,
    this.hintText = 'Search',
    this.onChanged,
    this.onSubmit,
    this.onClear,
    this.onStop,
    this.showStop = false,
    this.showSubmit = false,
  });

  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmit;
  final VoidCallback? onClear;
  final VoidCallback? onStop;
  final bool showStop;
  final bool showSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: colors.input,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.borderDefault),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: colors.fgPlaceholder),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted:
                  onSubmit != null && !showSubmit ? (_) => onSubmit!() : null,
              textInputAction: showSubmit
                  ? TextInputAction.none
                  : (onSubmit != null
                      ? TextInputAction.search
                      : TextInputAction.done),
              style: TextStyle(color: colors.fgDefault, fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hintText,
                hintStyle: TextStyle(color: colors.fgPlaceholder, fontSize: 12),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (showSubmit && onSubmit != null)
            IconButton(
              onPressed: onSubmit,
              icon: Icon(Icons.check, size: 16, color: colors.accentPrimary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Search',
            ),
          if (onClear != null)
            IconButton(
              onPressed: onClear,
              icon: Icon(Icons.close, size: 16, color: colors.fgMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Clear search',
            ),
          if ((showStop || onStop != null) && onStop != null)
            IconButton(
              onPressed: onStop,
              icon: Icon(Icons.stop, size: 16, color: colors.fgMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Stop',
            ),
        ],
      ),
    );
  }
}
