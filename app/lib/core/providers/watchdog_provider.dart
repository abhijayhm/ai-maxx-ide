import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../ws/ws_client.dart';
import 'app_providers.dart';
import 'ide_index_provider.dart';

final watchdogProvider =
    NotifierProvider<WatchdogNotifier, bool>(WatchdogNotifier.new);

class WatchdogNotifier extends Notifier<bool> {
  WsClient? _ws;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  bool build() {
    ref.onDispose(_disconnect);
    return false;
  }

  Future<void> connect() async {
    if (state) {
      return;
    }
    final session = await ref.read(sessionProvider.future);
    if (!session.isAuthenticated) {
      return;
    }

    final config = ref.read(appConfigProvider);
    config.serverUrl = AppConfig.normalizeServerUrl(session.serverUrl);
    config.apiKey = session.apiKey;

    _ws = WsClient(
      config: config,
      readHeaders: () => (
        apiKey: session.apiKey,
        deviceHash: session.deviceHash,
        workspaceId: session.activeWorkspaceId,
      ),
    );

    _sub = _ws!.messages.listen(_onMessage);
    await _ws!.connect('watchdog/');
    state = _ws!.isConnected;
  }

  void _onMessage(Map<String, dynamic> frame) {
    if (frame['type'] != 'watchdog') {
      return;
    }
    final event = frame['event'] as String? ?? '';
    final nodeJson = frame['node'] as Map<String, dynamic>?;
    if (nodeJson == null) {
      return;
    }
    if (event == 'created' || event == 'deleted') {
      unawaited(ref.read(ideIndexProvider.notifier).refreshAfterWatchdog());
    }
  }

  Future<void> disconnect() async {
    await _disconnect();
  }

  Future<void> _disconnect() async {
    await _sub?.cancel();
    _sub = null;
    await _ws?.disconnect();
    _ws = null;
    state = false;
  }
}
