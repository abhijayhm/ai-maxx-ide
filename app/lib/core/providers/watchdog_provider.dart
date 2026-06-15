import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_repository.dart';
import '../config/app_config.dart';
import '../ws/ws_client.dart';
import 'app_providers.dart';
import 'ide_index_provider.dart';

enum WorkbenchWsStatus { disconnected, connecting, active }

final watchdogProvider =
    NotifierProvider<WatchdogNotifier, WorkbenchWsStatus>(WatchdogNotifier.new);

class WatchdogNotifier extends Notifier<WorkbenchWsStatus> {
  WsClient? _ws;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  WorkbenchWsStatus build() {
    ref.keepAlive();
    ref.onDispose(() => _disconnect(silent: true));
    ref.listen(sessionProvider, (previous, next) {
      final wasReady = previous?.valueOrNull?.isReady ?? false;
      final isReady = next.valueOrNull?.isReady ?? false;
      if (!wasReady && isReady) {
        Future.microtask(connect);
      } else if (wasReady && !isReady) {
        Future.microtask(disconnect);
      }
    });
    return WorkbenchWsStatus.disconnected;
  }

  Future<void> connect({SessionSnapshot? session}) async {
    if (state == WorkbenchWsStatus.active ||
        state == WorkbenchWsStatus.connecting) {
      return;
    }

    final snapshot = session ?? ref.read(sessionProvider).valueOrNull;
    if (snapshot == null || !snapshot.isAuthenticated) {
      state = WorkbenchWsStatus.disconnected;
      return;
    }

    state = WorkbenchWsStatus.connecting;

    final config = ref.read(appConfigProvider);
    config.serverUrl = AppConfig.normalizeServerUrl(snapshot.serverUrl);
    config.apiKey = snapshot.apiKey;

    await _sub?.cancel();
    _sub = null;
    await _ws?.disconnect();
    _ws = WsClient(
      config: config,
      readHeaders: () => (
        apiKey: snapshot.apiKey,
        deviceHash: snapshot.deviceHash,
        workspaceId: snapshot.activeWorkspaceId,
      ),
    );

    _sub = _ws!.messages.listen(_onMessage);
    try {
      await _ws!.connect('watchdog/');
      state =
          _ws!.isConnected ? WorkbenchWsStatus.active : WorkbenchWsStatus.disconnected;
    } catch (_) {
      state = WorkbenchWsStatus.disconnected;
      await _disconnect(silent: true);
    }
  }

  void _onMessage(Map<String, dynamic> frame) {
    final type = frame['type'] as String? ?? '';
    if (type == 'connection_closed' || type == 'connection_error') {
      state = WorkbenchWsStatus.disconnected;
      final snapshot = ref.read(sessionProvider).valueOrNull;
      if (snapshot?.isAuthenticated == true) {
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (ref.read(sessionProvider).valueOrNull?.isAuthenticated == true) {
            unawaited(connect());
          }
        });
      } else {
        unawaited(_disconnect(silent: true));
      }
      return;
    }

    if (type != 'watchdog') {
      return;
    }
    final event = frame['event'] as String? ?? '';
    final nodeJson = frame['node'] as Map<String, dynamic>?;
    if (nodeJson == null) {
      return;
    }
    if (event == 'created' || event == 'deleted') {
      ref.read(ideIndexProvider.notifier).refreshAfterWatchdog();
    }
  }

  Future<void> disconnect() async {
    await _disconnect(silent: true);
    state = WorkbenchWsStatus.disconnected;
  }

  Future<void> retry() async {
    await _disconnect(silent: true);
    await connect();
  }

  Future<void> _disconnect({bool silent = false}) async {
    await _sub?.cancel();
    _sub = null;
    await _ws?.disconnect();
    _ws = null;
    if (!silent) {
      state = WorkbenchWsStatus.disconnected;
    }
  }
}
