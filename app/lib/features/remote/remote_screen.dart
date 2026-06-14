import 'package:flutter/material.dart';

import '../../theme/workbench_colors.dart';

enum _RemoteTab { trackpad, keyboard }

/// UI-only placeholder until remote WebRTC is reintroduced.
class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  _RemoteTab _tab = _RemoteTab.trackpad;
  String? _selectedKeyLayer;

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
              color: const Color(0xFF0F0F0F),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.desktop_windows_outlined,
                        size: 48, color: colors.fgInactive),
                    const SizedBox(height: 12),
                    Text(
                      'Remote desktop (coming soon)',
                      style: TextStyle(color: colors.fgMuted, fontSize: 13),
                    ),
                  ],
                ),
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
                  child: _tab == _RemoteTab.trackpad
                      ? _TrackpadPanel(colors: colors)
                      : _KeyboardPanel(
                          selectedLayer: _selectedKeyLayer,
                          onLayerTap: (layer) =>
                              setState(() => _selectedKeyLayer = layer),
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

class _TrackpadPanel extends StatelessWidget {
  const _TrackpadPanel({required this.colors});

  final WorkbenchColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: colors.input,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.borderDefault),
        ),
        alignment: Alignment.center,
        child: Text(
          'Trackpad disabled in this build',
          style: TextStyle(color: colors.fgMuted, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _KeyboardPanel extends StatelessWidget {
  const _KeyboardPanel({
    required this.selectedLayer,
    required this.onLayerTap,
  });

  final String? selectedLayer;
  final ValueChanged<String> onLayerTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    const layers = ['Fn', r'$#', '123'];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Keyboard staging disabled in this build',
            style: TextStyle(color: colors.fgDefault, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final layer in layers) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onLayerTap(layer),
                    child: Text(layer),
                  ),
                ),
                if (layer != layers.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
