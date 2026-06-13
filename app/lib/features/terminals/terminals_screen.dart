import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/terminal_provider.dart';
import '../../core/repositories/terminal_repository.dart';
import '../../theme/workbench_colors.dart';
import '../../theme/workbench_theme.dart';

class TerminalsScreen extends ConsumerStatefulWidget {
  const TerminalsScreen({super.key});

  @override
  ConsumerState<TerminalsScreen> createState() => _TerminalsScreenState();
}

class _TerminalsScreenState extends ConsumerState<TerminalsScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(terminalProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final terminal = ref.watch(terminalProvider);

    ref.listen(terminalProvider, (previous, next) {
      if (previous?.output != next.output) {
        _scrollToBottom();
      }
    });

    TerminalSession? active;
    for (final session in terminal.sessions) {
      if (session.id == terminal.activeId) {
        active = session;
        break;
      }
    }

    return ColoredBox(
      color: colors.canvas,
      child: Column(
        children: [
          if (terminal.loading)
            LinearProgressIndicator(
              minHeight: 2,
              color: colors.accentPrimary,
              backgroundColor: colors.borderSubtle,
            ),
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.elevated,
              border: Border(bottom: BorderSide(color: colors.borderDefault)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: terminal.connected
                        ? colors.statusSuccess
                        : colors.fgInactive,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active?.name ?? 'No terminal',
                    style: TextStyle(color: colors.fgStrong, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: terminal.loading
                      ? null
                      : () => ref.read(terminalProvider.notifier).create(),
                  icon: Icon(Icons.add, color: colors.fgMuted, size: 18),
                  tooltip: 'New terminal',
                ),
                IconButton(
                  onPressed: terminal.activeId == null
                      ? null
                      : () => ref.read(terminalProvider.notifier).deleteActive(),
                  icon: Icon(Icons.delete_outline, color: colors.fgMuted, size: 18),
                  tooltip: 'Delete terminal',
                ),
              ],
            ),
          ),
          Expanded(
            child: terminal.error != null && terminal.output.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        terminal.error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.statusError, fontSize: 13),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      terminal.output.isEmpty
                          ? 'Terminal output will appear here…'
                          : terminal.output,
                      style: workbenchMonoStyle(
                        context,
                        size: 13,
                        color: terminal.output.isEmpty
                            ? colors.fgMuted
                            : colors.fgDefault,
                      ),
                    ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: colors.elevated,
              border: Border(top: BorderSide(color: colors.borderSubtle)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    enabled: terminal.connected,
                    style: workbenchMonoStyle(context, size: 13),
                    decoration: InputDecoration(
                      hintText: terminal.connected
                          ? 'Type command…'
                          : 'Connecting…',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (value) {
                      if (value.isEmpty) {
                        return;
                      }
                      ref.read(terminalProvider.notifier).sendInput('$value\n');
                      _inputController.clear();
                    },
                  ),
                ),
              ],
            ),
          ),
          if (terminal.sessions.isNotEmpty)
            SizedBox(
              height: 120,
              child: ListView.builder(
                itemCount: terminal.sessions.length,
                itemBuilder: (context, index) {
                  final session = terminal.sessions[index];
                  final selected = session.id == terminal.activeId;
                  return Material(
                    color: index.isEven ? colors.canvas : colors.chrome,
                    child: ListTile(
                      dense: true,
                      leading: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: session.status == 'active'
                              ? colors.statusSuccess
                              : colors.fgInactive,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(
                        session.name,
                        style: workbenchMonoStyle(context, size: 12),
                      ),
                      subtitle: Text(
                        session.cwd,
                        style: TextStyle(color: colors.fgMuted, fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: selected,
                      onTap: () =>
                          ref.read(terminalProvider.notifier).select(session.id),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
