import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/app_router.dart';
import 'theme/workbench_theme.dart';

class AiMaxxIdeApp extends ConsumerWidget {
  const AiMaxxIdeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'AI Maxx IDE',
      debugShowCheckedModeBanner: false,
      theme: buildWorkbenchTheme(),
      routerConfig: router,
    );
  }
}
