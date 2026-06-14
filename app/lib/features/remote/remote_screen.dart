import 'dart:async';

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
            flex: 2,
            child: _VideoPane(
              colors: colors,
              loading: remote.isLoading,
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
            flex: 3,
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
                          sensitivity: remote.trackpadSensitivity,
                          onSensitivityChanged: (value) => ref
                              .read(remoteProvider.notifier)
                              .setTrackpadSensitivity(value),
                          onSwipeDelta: (dx, dy) => ref
                              .read(remoteProvider.notifier)
                              .pointerDelta(dx, dy),
                          onClick: () =>
                              ref.read(remoteProvider.notifier).click(button: 'left'),
                          onRightClick: () =>
                              ref.read(remoteProvider.notifier).click(button: 'right'),
                        )
                      : RemoteKeyboard(
                          controller: _keyboardController,
                          onCommit: (keys, modifiers) => ref
                              .read(remoteProvider.notifier)
                              .commitKeys(keys, modifiers),
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
    required this.loading,
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
  final bool loading;
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
          final hasVideo =
              videoReady && renderer != null && renderer!.srcObject != null;

          return Stack(
            fit: StackFit.expand,
            children: [
              if (hasVideo)
                GestureDetector(
                  onPanUpdate: (details) {
                    final x = (details.localPosition.dx / constraints.maxWidth)
                        .clamp(0.0, 1.0);
                    final y = (details.localPosition.dy / constraints.maxHeight)
                        .clamp(0.0, 1.0);
                    onPointerMove(x, y);
                  },
                  onTap: onClick,
                  child: RTCVideoView(
                    renderer!,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                  ),
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                            style: TextStyle(
                              color: colors.statusError,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      if (!loading) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: onReconnect,
                          child: const Text('Reconnect'),
                        ),
                      ],
                    ],
                  ),
                ),
              if (loading)
                ColoredBox(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          connecting
                              ? 'Connecting remote desktop…'
                              : 'Starting video stream…',
                          style: TextStyle(color: colors.fgDefault, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
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

class _TrackpadPanel extends StatefulWidget {
  const _TrackpadPanel({
    required this.colors,
    required this.enabled,
    required this.sensitivity,
    required this.onSensitivityChanged,
    required this.onSwipeDelta,
    required this.onClick,
    required this.onRightClick,
  });

  final WorkbenchColors colors;
  final bool enabled;
  final double sensitivity;
  final ValueChanged<double> onSensitivityChanged;
  final void Function(double dx, double dy) onSwipeDelta;
  final VoidCallback onClick;
  final VoidCallback onRightClick;

  @override
  State<_TrackpadPanel> createState() => _TrackpadPanelState();
}

class _TrackpadPanelState extends State<_TrackpadPanel> {
  static const _sendInterval = Duration(milliseconds: 33); // ~30 Hz

  double _pendingDx = 0;
  double _pendingDy = 0;
  Timer? _sendTimer;

  @override
  void dispose() {
    _stopSendLoop(flush: true);
    super.dispose();
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: widget.colors.elevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) {
        var value = widget.sensitivity;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trackpad sensitivity',
                    style: TextStyle(
                      color: widget.colors.fgStrong,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Higher values move the pointer faster.',
                    style: TextStyle(color: widget.colors.fgMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: value,
                          min: 0.25,
                          max: 4.0,
                          divisions: 15,
                          label: value.toStringAsFixed(2),
                          onChanged: (next) {
                            setSheetState(() => value = next);
                            widget.onSensitivityChanged(next);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          value.toStringAsFixed(2),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: widget.colors.fgDefault,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _flushDelta() {
    if (_pendingDx == 0 && _pendingDy == 0) {
      return;
    }
    widget.onSwipeDelta(_pendingDx, _pendingDy);
    _pendingDx = 0;
    _pendingDy = 0;
  }

  void _startSendLoop() {
    _sendTimer ??= Timer.periodic(_sendInterval, (_) => _flushDelta());
  }

  void _stopSendLoop({bool flush = false}) {
    _sendTimer?.cancel();
    _sendTimer = null;
    if (flush) {
      _flushDelta();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              GestureDetector(
                onPanStart: widget.enabled ? (_) => _startSendLoop() : null,
                onPanUpdate: widget.enabled
                    ? (details) {
                        _pendingDx +=
                            details.delta.dx / constraints.maxWidth * widget.sensitivity;
                        _pendingDy +=
                            details.delta.dy / constraints.maxHeight * widget.sensitivity;
                      }
                    : null,
                onPanEnd: widget.enabled ? (_) => _stopSendLoop(flush: true) : null,
                onPanCancel: widget.enabled ? () => _stopSendLoop(flush: true) : null,
                onTap: widget.enabled ? widget.onClick : null,
                onLongPress: widget.enabled ? widget.onRightClick : null,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.colors.input,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: widget.colors.borderDefault),
                  ),
                  child: SizedBox.expand(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          widget.enabled
                              ? 'Drag to move pointer\nTap = Left Click, Long Tap = Right Click'
                              : 'Connect remote desktop to use trackpad',
                          style: TextStyle(
                            color: widget.colors.fgMuted,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: _openSettings,
                  icon: Icon(Icons.settings, size: 20, color: widget.colors.fgMuted),
                  tooltip: 'Trackpad settings',
                  style: IconButton.styleFrom(
                    backgroundColor: widget.colors.chrome.withValues(alpha: 0.9),
                    minimumSize: const Size(32, 32),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
