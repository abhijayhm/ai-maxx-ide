import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/terminals_provider.dart';
import '../../core/terminals/terminal_models.dart';
import '../../theme/workbench_colors.dart';
import '../../theme/workbench_theme.dart';

class TerminalsScreen extends ConsumerStatefulWidget {
  const TerminalsScreen({super.key});

  @override
  ConsumerState<TerminalsScreen> createState() => _TerminalsScreenState();
}

class _TerminalsScreenState extends ConsumerState<TerminalsScreen> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  String _lastInput = '';
  int _lastCols = 80;
  int _lastRows = 24;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(terminalsProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    final text = _inputController.text;
    final notifier = ref.read(terminalsProvider.notifier);
    if (text.length > _lastInput.length) {
      notifier.sendInput(text.substring(_lastInput.length));
    } else if (text.length < _lastInput.length) {
      notifier.sendBackspace();
    }
    _lastInput = text;
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final state = ref.watch(terminalsProvider);
    final active = state.activeSession;

    ref.listen(terminalsProvider.select((s) => s.output), (prev, next) {
      if (next != prev) {
        _scrollToEnd();
      }
    });

    return ColoredBox(
      color: colors.canvas,
      child: Column(
        children: [
          _SessionBar(
            sessions: state.sessions,
            activeId: state.activeId,
            attached: state.attached,
            onCreate: () => ref.read(terminalsProvider.notifier).createSession(),
            onSelect: (id) => ref.read(terminalsProvider.notifier).selectSession(id),
            onClose: (id) => ref.read(terminalsProvider.notifier).closeSession(id),
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                state.error!,
                style: TextStyle(color: colors.statusError, fontSize: 12),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final charWidth = 7.8;
                final lineHeight = 18.0;
                final cols =
                    (constraints.maxWidth / charWidth).floor().clamp(20, 200);
                final rows =
                    (constraints.maxHeight / lineHeight).floor().clamp(8, 120);
                if (state.attached &&
                    (cols != _lastCols || rows != _lastRows)) {
                  _lastCols = cols;
                  _lastRows = rows;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    ref
                        .read(terminalsProvider.notifier)
                        .resize(cols: cols, rows: rows);
                  });
                }

                return ColoredBox(
                  color: const Color(0xFF0F0F0F),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      state.output.isEmpty
                          ? (state.loading
                              ? 'Loading terminal…'
                              : 'Terminal output will appear here…')
                          : state.output,
                      style: workbenchMonoStyle(
                        context,
                        size: 13,
                        color: state.output.isEmpty
                            ? colors.fgMuted
                            : colors.fgDefault,
                      ),
                    ),
                  ),
                );
              },
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
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: state.attached ? colors.statusSuccess : colors.fgInactive,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active == null
                        ? 'No terminal'
                        : '${active.name} · ${state.shell ?? active.shell}',
                    style: TextStyle(color: colors.fgMuted, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            color: colors.elevated,
            child: TextField(
              controller: _inputController,
              enabled: state.attached,
              style: workbenchMonoStyle(context, size: 13),
              decoration: InputDecoration(
                hintText: state.attached
                    ? 'Type command (Enter sends newline)'
                    : 'Connect a terminal to type…',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: colors.input,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.borderDefault),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.borderDefault),
                ),
              ),
              onSubmitted: (_) {
                ref.read(terminalsProvider.notifier).sendInput('\n');
                _inputController.clear();
                _lastInput = '';
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionBar extends StatelessWidget {
  const _SessionBar({
    required this.sessions,
    required this.activeId,
    required this.attached,
    required this.onCreate,
    required this.onSelect,
    required this.onClose,
  });

  final List<TerminalSession> sessions;
  final int? activeId;
  final bool attached;
  final VoidCallback onCreate;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.elevated,
        border: Border(bottom: BorderSide(color: colors.borderDefault)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 18),
            color: colors.accentPrimary,
            tooltip: 'New terminal',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final session in sessions)
                  _SessionTab(
                    label: session.name,
                    selected: session.id == activeId,
                    attached: attached && session.id == activeId,
                    onTap: () => onSelect(session.id),
                    onClose: () => onClose(session.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTab extends StatelessWidget {
  const _SessionTab({
    required this.label,
    required this.selected,
    required this.attached,
    required this.onTap,
    required this.onClose,
  });

  final String label;
  final bool selected;
  final bool attached;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;

    return Padding(
      padding: const EdgeInsets.only(right: 4, top: 4, bottom: 4),
      child: Material(
        color: selected ? colors.chrome : colors.input,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (attached)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colors.statusSuccess,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? colors.fgStrong : colors.fgMuted,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onClose,
                  child: Icon(Icons.close, size: 14, color: colors.fgMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
