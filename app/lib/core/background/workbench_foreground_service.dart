import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Android foreground service so the OS does not suspend WS while backgrounded.
class WorkbenchForegroundService {
  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static bool _initialized = false;

  static Future<void> init() async {
    if (!_supported || _initialized) {
      return;
    }
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'aimaxx_workbench_session',
        channelName: 'Server connection',
        channelDescription:
            'Keeps AI Maxx IDE connected to your server in the background',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  static Future<void> start() async {
    if (!_supported || !_initialized) {
      return;
    }
    if (await FlutterForegroundTask.isRunningService) {
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'AI Maxx IDE',
      notificationText: 'Connected to server',
      callback: _foregroundTaskCallback,
    );
  }

  static Future<void> stop() async {
    if (!_supported) {
      return;
    }
    if (!await FlutterForegroundTask.isRunningService) {
      return;
    }
    await FlutterForegroundTask.stopService();
  }
}

@pragma('vm:entry-point')
void _foregroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_WorkbenchTaskHandler());
}

class _WorkbenchTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTaskRemoved) async {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}
}
