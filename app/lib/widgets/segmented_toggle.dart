import 'package:flutter/material.dart';

import '../theme/workbench_colors.dart';

class SegmentedToggle extends StatelessWidget {
  const SegmentedToggle({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => onChanged(i),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: selectedIndex == i ? colors.accentPrimary : colors.input,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: selectedIndex == i
                        ? colors.accentPrimary
                        : colors.borderDefault,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  options[i],
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: selectedIndex == i
                        ? colors.fgStrong
                        : colors.fgDefault,
                    fontSize: 12,
                    fontWeight:
                        selectedIndex == i ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
