import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/providers/remote_provider.dart';
import '../../core/providers/sync_provider.dart';
import '../../theme/workbench_colors.dart';

class RemoteScreen extends ConsumerStatefulWidget {
  const RemoteScreen({super.key});

  @override
  ConsumerState<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends ConsumerState<RemoteScreen> {
  _RemoteTab _tab = _RemoteTab.trackpad;
  String? _selectedKeyLayer;

  @override
  void initState() {
    super.initState();
    Future.microtask(_connectRemoteWhenReady);
  }

  void _connectRemoteWhenReady() {
    final sync = ref.read(workspaceSyncProvider);
    if (!sync.isActive) {
      ref.read(remoteProvider.notifier).connect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final remote = ref.watch(remoteProvider);

    ref.listen(workspaceSyncProvider, (previous, next) {
      final wasActive = previous?.isActive ?? false;
      if (wasActive && !next.isActive && !remote.connected) {
        ref.read(remoteProvider.notifier).connect();
      }
    });

    return ColoredBox(
      color: colors.canvas,
      child: Column(
        children: [
          Expanded(
            flex: 1,
            child: _DesktopVideoPanel(
              remote: remote,
              colors: colors,
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
                      ? _TrackpadPanel(
                          enabled: remote.connected,
                          onMove: (x, y) => ref
                              .read(remoteProvider.notifier)
                              .pointerMove(x, y),
                          onLeftClick: () =>
                              ref.read(remoteProvider.notifier).leftClick(),
                          onRightClick: () =>
                              ref.read(remoteProvider.notifier).rightClick(),
                        )
                      : _KeyboardPanel(
                          stagedCount: remote.stagedCount,
                          selectedLayer: _selectedKeyLayer,
                          onLayerTap: (layer) =>
                              setState(() => _selectedKeyLayer = layer),
                          onStageKey: (key) =>
                              ref.read(remoteProvider.notifier).stageKey(key),
                          onClear: () =>
                              ref.read(remoteProvider.notifier).clear(),
                          onDispatch: () =>
                              ref.read(remoteProvider.notifier).dispatch(),
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

class _DesktopVideoPanel extends StatelessWidget {
  const _DesktopVideoPanel({
    required this.remote,
    required this.colors,
  });

  final RemoteState remote;
  final WorkbenchColors colors;

  @override
  Widget build(BuildContext context) {
    final renderer = remote.renderer;

    return Container(
      width: double.infinity,
      color: const Color(0xFF0F0F0F),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (remote.videoReady && renderer != null)
            RTCVideoView(
              renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
            )
          else
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.desktop_windows_outlined,
                      size: 48, color: colors.fgInactive),
                  const SizedBox(height: 12),
                  Text(
                    remote.videoReady
                        ? 'Desktop stream active'
                        : 'Connecting to desktop…',
                    style: TextStyle(color: colors.fgMuted, fontSize: 13),
                  ),
                  if (remote.status.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        remote.status,
                        style: TextStyle(
                          color: colors.fgInactive,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  if (remote.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        remote.error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.statusError,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (!remote.videoReady)
            const Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (remote.videoReady)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.elevated.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colors.statusSuccess,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Live',
                      style: TextStyle(color: colors.fgDefault, fontSize: 11),
                    ),
                  ],
                ),
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

class _TrackpadPanel extends StatelessWidget {
  const _TrackpadPanel({
    required this.enabled,
    required this.onMove,
    required this.onLeftClick,
    required this.onRightClick,
  });

  final bool enabled;
  final void Function(double x, double y) onMove;
  final VoidCallback onLeftClick;
  final VoidCallback onRightClick;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Listener(
                  onPointerMove: enabled
                      ? (event) {
                          final x =
                              event.localPosition.dx / constraints.maxWidth;
                          final y =
                              event.localPosition.dy / constraints.maxHeight;
                          onMove(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));
                        }
                      : null,
                  child: GestureDetector(
                    onTap: enabled ? onLeftClick : null,
                    onSecondaryTap: enabled ? onRightClick : null,
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: colors.input,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.borderDefault),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        enabled
                            ? 'Move · tap = left · long-press area = trackpad'
                            : 'Waiting for connection…',
                        style: TextStyle(color: colors.fgMuted, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SecondaryButton(
                  label: 'Left',
                  onTap: enabled ? onLeftClick : () {},
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SecondaryButton(
                  label: 'Right',
                  onTap: enabled ? onRightClick : () {},
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KeyboardPanel extends StatelessWidget {
  const _KeyboardPanel({
    required this.stagedCount,
    required this.selectedLayer,
    required this.onLayerTap,
    required this.onStageKey,
    required this.onClear,
    required this.onDispatch,
  });

  final int stagedCount;
  final String? selectedLayer;
  final ValueChanged<String> onLayerTap;
  final ValueChanged<String> onStageKey;
  final VoidCallback onClear;
  final VoidCallback onDispatch;

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
            stagedCount > 0
                ? '$stagedCount key(s) staged'
                : 'Stage keys then dispatch',
            style: TextStyle(color: colors.fgDefault, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final layer in layers) ...[
                Expanded(
                  child: _SecondaryButton(
                    label: layer,
                    selected: selectedLayer == layer,
                    onTap: () => onLayerTap(layer),
                  ),
                ),
                if (layer != layers.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                onPressed: onClear,
                icon: Icon(Icons.close, color: colors.statusError),
                tooltip: 'Clear staging',
              ),
              IconButton(
                onPressed: () => onStageKey(selectedLayer ?? 'enter'),
                icon: Icon(Icons.add, color: colors.fgMuted),
                tooltip: 'Add to staging',
              ),
              IconButton(
                onPressed: onDispatch,
                icon: Icon(Icons.check, color: colors.statusSuccess),
                tooltip: 'Dispatch to remote',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? colors.inputHover : colors.input,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? colors.accentPrimary : colors.borderDefault,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: colors.fgDefault,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
