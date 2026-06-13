import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/app_providers.dart';
import '../features/menu/git_menu_screen.dart';
import '../features/menu/workspace_menu_screen.dart';
import '../features/projects/projects_screen.dart';
import '../features/remote/remote_screen.dart';
import '../features/shell/workbench_scaffold.dart';
import '../features/terminals/terminals_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen(sessionProvider, (_, _) => refresh.value++);

  final isReady = ref.read(sessionProvider).valueOrNull?.isReady ?? false;

  return GoRouter(
    refreshListenable: refresh,
    initialLocation: isReady ? '/projects' : '/menu/workspace',
    redirect: (context, state) {
      final snapshot = ref.read(sessionProvider).valueOrNull;
      final ready = snapshot?.isReady ?? false;
      final onMenu = state.matchedLocation.startsWith('/menu');
      final onShellTab = state.matchedLocation == '/projects' ||
          state.matchedLocation == '/terminals' ||
          state.matchedLocation == '/remote';

      if (!ready && onShellTab) {
        return '/menu/workspace';
      }
      if (!ready && state.matchedLocation == '/menu/git') {
        return '/menu/workspace';
      }
      if (ready && state.matchedLocation == '/menu/workspace') {
        return null;
      }
      if (!ready && !onMenu) {
        return '/menu/workspace';
      }
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => WorkbenchScaffold(child: child),
        routes: [
          GoRoute(
            path: '/projects',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ProjectsScreen()),
          ),
          GoRoute(
            path: '/terminals',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: TerminalsScreen()),
          ),
          GoRoute(
            path: '/remote',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: RemoteScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/menu/workspace',
        pageBuilder: (context, state) => CustomTransitionPage(
          child: const WorkspaceMenuScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(-1, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            );
          },
        ),
      ),
      GoRoute(
        path: '/menu/git',
        pageBuilder: (context, state) => CustomTransitionPage(
          child: const GitMenuScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(-1, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            );
          },
        ),
      ),
    ],
  );
});
