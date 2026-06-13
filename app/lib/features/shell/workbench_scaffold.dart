import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';
import '../../theme/workbench_colors.dart';
import '../../widgets/workbench_search_field.dart';

class WorkbenchScaffold extends ConsumerWidget {
  const WorkbenchScaffold({super.key, required this.child});

  final Widget child;

  static const _tabs = [
  _TabSpec('/projects', 'Projects'),
  _TabSpec('/terminals', 'Terminals'),
  _TabSpec('/remote', 'Remote'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.workbenchColors;
    final session = ref.watch(sessionProvider).valueOrNull;
    final isReady = session?.isReady ?? false;
    final location = GoRouterState.of(context).matchedLocation;
    final onMenu = location.startsWith('/menu');
    final showShellChrome = !onMenu;

    return Scaffold(
      backgroundColor: colors.app,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (showShellChrome)
              _WorkbenchHeader(
                onMenuTap: () => context.push('/menu/workspace'),
              ),
            Expanded(child: child),
            if (showShellChrome)
              _WorkbenchBottomNav(
                tabs: _tabs,
                currentPath: location,
                enabled: isReady,
                onTabTap: (path) {
                  if (!isReady) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Authenticate and open a workspace to unlock tabs.',
                        ),
                      ),
                    );
                    context.push('/menu/workspace');
                    return;
                  }
                  context.go(path);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec(this.path, this.label);

  final String path;
  final String label;
}

class _WorkbenchHeader extends StatelessWidget {
  const _WorkbenchHeader({required this.onMenuTap});

  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: colors.chrome,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onMenuTap,
            icon: Icon(Icons.menu, color: colors.fgDefault),
            tooltip: 'Menu',
          ),
          const Expanded(
            child: WorkbenchSearchField(),
          ),
        ],
      ),
    );
  }
}

class _WorkbenchBottomNav extends StatelessWidget {
  const _WorkbenchBottomNav({
    required this.tabs,
    required this.currentPath,
    required this.enabled,
    required this.onTabTap,
  });

  final List<_TabSpec> tabs;
  final String currentPath;
  final bool enabled;
  final ValueChanged<String> onTabTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.chrome,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 32,
          child: Row(
            children: [
              for (final tab in tabs)
                Expanded(
                  child: _BottomTab(
                    label: tab.label,
                    selected: currentPath == tab.path,
                    enabled: enabled,
                    onTap: () => onTabTap(tab.path),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomTab extends StatelessWidget {
  const _BottomTab({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final active = selected && enabled;

    return Material(
      color: active ? colors.canvas : colors.chrome,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (active)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(height: 2, color: colors.accentPrimary),
              ),
            Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: enabled
                      ? (active ? colors.fgStrong : colors.fgDefault)
                      : colors.fgInactive,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
