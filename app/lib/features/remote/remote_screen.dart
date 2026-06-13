import 'package:flutter/material.dart';

import '../../theme/workbench_colors.dart';

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  _RemoteTab _tab = _RemoteTab.trackpad;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return ColoredBox(
      color: colors.canvas,
      child: Column(
        children: [
          Expanded(
            flex: 1,
            child: Container(
              width: double.infinity,
              color: colors.elevated,
              alignment: Alignment.center,
              child: Text(
                'Desktop video stub — WebRTC /ws/remote/.',
                style: TextStyle(color: colors.fgMuted, fontSize: 13),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Row(
                  children: [
                    _RemoteTabButton(
                      label: 'Trackpad',
                      selected: _tab == _RemoteTab.trackpad,
                      onTap: () => setState(() => _tab = _RemoteTab.trackpad),
                    ),
                    _RemoteTabButton(
                      label: 'Keyboard',
                      selected: _tab == _RemoteTab.keyboard,
                      onTap: () => setState(() => _tab = _RemoteTab.keyboard),
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      _tab == _RemoteTab.trackpad
                          ? 'Trackpad gestures stub.'
                          : 'Keyboard staging stub.',
                      style: TextStyle(color: colors.fgMuted, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _RemoteTab { trackpad, keyboard }

class _RemoteTabButton extends StatelessWidget {
  const _RemoteTabButton({
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
            color: colors.chrome,
            border: Border(
              top: BorderSide(
                color: selected ? colors.accentPrimary : Colors.transparent,
                width: 2,
              ),
              bottom: BorderSide(color: colors.borderSubtle),
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
