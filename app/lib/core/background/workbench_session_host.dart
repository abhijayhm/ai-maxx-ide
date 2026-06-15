import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_repository.dart';
import '../providers/agent_provider.dart';
import '../providers/app_providers.dart';
import '../providers/watchdog_provider.dart';
import 'workbench_foreground_service.dart';

/// Pins persistent workbench sockets and reconnects after resume (no disconnect on pause).
class WorkbenchSessionHost extends ConsumerStatefulWidget {
  const WorkbenchSessionHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WorkbenchSessionHost> createState() =>
      _WorkbenchSessionHostState();
}

class _WorkbenchSessionHostState extends ConsumerState<WorkbenchSessionHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncForegroundService(ref.read(sessionProvider).valueOrNull);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    final snapshot = ref.read(sessionProvider).valueOrNull;
    if (snapshot?.isAuthenticated != true) {
      return;
    }
    unawaited(ref.read(watchdogProvider.notifier).retry());
    if (snapshot?.isReady == true) {
      unawaited(ref.read(agentProvider.notifier).ensureConnected());
    }
  }

  void _syncForegroundService(SessionSnapshot? snapshot) {
    if (snapshot?.isReady == true) {
      unawaited(WorkbenchForegroundService.start());
    } else {
      unawaited(WorkbenchForegroundService.stop());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep session-scoped providers alive for the whole app lifetime.
    ref.watch(watchdogProvider);
    ref.watch(agentProvider);

    ref.listen<AsyncValue<SessionSnapshot>>(sessionProvider, (previous, next) {
      _syncForegroundService(next.valueOrNull);
    });

    return widget.child;
  }
}
