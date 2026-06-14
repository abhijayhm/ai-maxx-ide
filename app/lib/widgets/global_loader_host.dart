import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/global_loader_provider.dart';
import 'workbench_loader_overlay.dart';

/// Wraps the app tree and shows a centered loader when [globalLoaderProvider] is set.
class GlobalLoaderHost extends ConsumerWidget {
  const GlobalLoaderHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(globalLoaderProvider);

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (message != null) WorkbenchLoaderOverlay(message: message),
      ],
    );
  }
}
