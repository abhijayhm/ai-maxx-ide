import 'package:flutter_riverpod/flutter_riverpod.dart';

final globalLoaderProvider =
    NotifierProvider<GlobalLoaderNotifier, String?>(GlobalLoaderNotifier.new);

/// Tracks one [show] call; [release] is idempotent.
class LoaderHandle {
  LoaderHandle(this._notifier);

  final GlobalLoaderNotifier _notifier;
  bool _released = false;

  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _notifier.hide();
  }
}

class GlobalLoaderNotifier extends Notifier<String?> {
  int _depth = 0;

  @override
  String? build() => null;

  LoaderHandle acquire(String message) {
    _depth++;
    state = message;
    return LoaderHandle(this);
  }

  void show(String message) {
    acquire(message);
  }

  void hide() {
    if (_depth <= 0) {
      return;
    }
    _depth--;
    if (_depth == 0) {
      state = null;
    }
  }

  void reset() {
    _depth = 0;
    state = null;
  }

  Future<T> run<T>(String message, Future<T> Function() body) async {
    final handle = acquire(message);
    try {
      return await body();
    } finally {
      handle.release();
    }
  }
}

/// WebSocket frame types that should end an in-flight loader.
bool isWsTerminalFrame(String type) {
  return type == 'error' ||
      type == 'connection_error' ||
      type == 'connection_closed' ||
      type == 'cancelled';
}
