import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/providers/remote_provider.dart';
import '../../theme/workbench_colors.dart';
import '../../widgets/remote_keyboard.dart';

enum _RemoteTab { trackpad, keyboard }

class RemoteScreen extends ConsumerStatefulWidget {
  const RemoteScreen({super.key});

  @override
  ConsumerState<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends ConsumerState<RemoteScreen> {
  _RemoteTab _tab = _RemoteTab.trackpad;
  final _keyboardController = RemoteKeyboardController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(remoteProvider.notifier).connect();
    });
  }

  @override
  void dispose() {
    _keyboardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final remote = ref.watch(remoteProvider);
    final client = ref.watch(remoteClientProvider);

    return ColoredBox(
      color: colors.canvas,
      child: Column(
        children: [
          Expanded(
            flex: 5,
            child: _VideoPane(
              colors: colors,
              connecting: remote.connecting,
              connected: remote.connected,
              videoReady: remote.videoReady,
              error: remote.error,
              renderer: client?.webrtc.renderer,
              onPointerMove: (x, y) =>
                  ref.read(remoteProvider.notifier).pointerMove(x, y),
              onClick: () => ref.read(remoteProvider.notifier).click(),
              onReconnect: () => ref.read(remoteProvider.notifier).connect(),
            ),
          ),
          if (remote.stagedCount > 0)
            _StagingBar(
              count: remote.stagedCount,
              onDispatch: () => ref.read(remoteProvider.notifier).dispatchStaging(),
              onClear: () => ref.read(remoteProvider.notifier).clearStaging(),
            ),
          Expanded(
            flex: 4,
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
                          colors: colors,
                          enabled: remote.connected,
                          onPointerMove: (x, y) =>
                              ref.read(remoteProvider.notifier).pointerMove(x, y),
                          onClick: () =>
                              ref.read(remoteProvider.notifier).click(button: 'left'),
                          onRightClick: () =>
                              ref.read(remoteProvider.notifier).click(button: 'right'),
                        )
                      : RemoteKeyboard(
                          controller: _keyboardController,
                          onKey: (value, modifiers) => ref
                              .read(remoteProvider.notifier)
                              .sendKey(value, modifiers: modifiers),
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

class _VideoPane extends StatelessWidget {
  const _VideoPane({
    required this.colors,
    required this.connecting,
    required this.connected,
    required this.videoReady,
    required this.error,
    required this.renderer,
    required this.onPointerMove,
    required this.onClick,
    required this.onReconnect,
  });

  final WorkbenchColors colors;
  final bool connecting;
  final bool connected;
  final bool videoReady;
  final String? error;
  final RTCVideoRenderer? renderer;
  final void Function(double x, double y) onPointerMove;
  final VoidCallback onClick;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0F0F0F),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (videoReady && renderer != null && renderer!.srcObject != null) {
            return GestureDetector(
              onPanUpdate: (details) {
                final x =
                    (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                final y =
                    (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
                onPointerMove(x, y);
              },
              onTap: onClick,
              child: RTCVideoView(
                renderer!,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              ),
            );
          }

          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (connecting)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    Icons.desktop_windows_outlined,
                    size: 48,
                    color: colors.fgInactive,
                  ),
                const SizedBox(height: 12),
                Text(
                  connecting
                      ? 'Connecting remote desktop…'
                      : connected && !videoReady
                          ? 'Waiting for video stream…'
                          : 'Remote desktop',
                  style: TextStyle(color: colors.fgMuted, fontSize: 13),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.statusError, fontSize: 12),
                    ),
                  ),
                ],
                if (!connecting) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: onReconnect,
                    child: const Text('Reconnect'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StagingBar extends StatelessWidget {
  const _StagingBar({
    required this.count,
    required this.onDispatch,
    required this.onClear,
  });

  final int count;
  final VoidCallback onDispatch;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: colors.elevated,
      child: Row(
        children: [
          Text(
            '$count staged input(s)',
            style: TextStyle(color: colors.fgMuted, fontSize: 12),
          ),
          const Spacer(),
          TextButton(onPressed: onClear, child: const Text('Clear')),
          const SizedBox(width: 8),
          FilledButton(onPressed: onDispatch, child: const Text('Send')),
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
  const _TrackpadPanel({
    required this.colors,
    required this.enabled,
    required this.onPointerMove,
    required this.onClick,
    required this.onRightClick,
  });

  final WorkbenchColors colors;
  final bool enabled;
  final void Function(double x, double y) onPointerMove;
  final VoidCallback onClick;
  final VoidCallback onRightClick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onPanUpdate: enabled
                ? (details) {
                    final x = (details.localPosition.dx / constraints.maxWidth)
                        .clamp(0.0, 1.0);
                    final y = (details.localPosition.dy / constraints.maxHeight)
                        .clamp(0.0, 1.0);
                    onPointerMove(x, y);
                  }
                : null,
            onTap: enabled ? onClick : null,
            onLongPress: enabled ? onRightClick : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.input,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.borderDefault),
              ),
              child: Center(
                child: Text(
                  enabled
                      ? 'Drag to move pointer · tap = left click · long-press = right'
                      : 'Connect remote desktop to use trackpad',
                  style: TextStyle(color: colors.fgMuted, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
