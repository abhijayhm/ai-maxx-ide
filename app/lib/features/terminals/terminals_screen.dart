import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/terminals_provider.dart';
import '../../core/terminals/terminal_models.dart';
import '../../theme/workbench_colors.dart';
import '../../theme/workbench_theme.dart';

/// Classic terminal colours (near-black canvas, light monospace text).
const _terminalBg = Color(0xFF0C0C0C);
const _terminalFg = Color(0xFFCCCCCC);

/// Windows shells exposed when creating a terminal session.
const _shellOptions = [
  (id: 'cmd', label: 'Command Prompt (cmd)'),
  (id: 'powershell', label: 'PowerShell'),
];

class TerminalsScreen extends ConsumerStatefulWidget {
  const TerminalsScreen({super.key});

  @override
  ConsumerState<TerminalsScreen> createState() => _TerminalsScreenState();
}

class _TerminalsScreenState extends ConsumerState<TerminalsScreen> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(terminalsProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _inputFocus.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  void _ensureInputFocused() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ref.read(terminalsProvider).attached) {
        return;
      }
      _inputFocus.requestFocus();
    });
  }

  void _submitCommand() {
    final state = ref.read(terminalsProvider);
    if (!state.attached || state.executing) {
      return;
    }
    final text = _inputController.text;
    if (text.trim().isEmpty) {
      return;
    }
    ref.read(terminalsProvider.notifier).sendInput(text);
    _inputController.clear();
    _ensureInputFocused();
  }

  Future<void> _promptCreateTerminal() async {
    var selected = _shellOptions.first.id;

    final shell = await showDialog<String>(
      context: context,
      builder: (context) {
        final colors = context.workbenchColors;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: colors.elevated,
              title: Text(
                'New terminal',
                style: TextStyle(color: colors.fgStrong, fontSize: 16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final option in _shellOptions)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        selected == option.id
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: selected == option.id
                            ? colors.accentPrimary
                            : colors.fgMuted,
                        size: 22,
                      ),
                      title: Text(
                        option.label,
                        style: TextStyle(
                          color: colors.fgDefault,
                          fontSize: 14,
                        ),
                      ),
                      onTap: () => setDialogState(() => selected = option.id),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: TextStyle(color: colors.fgMuted)),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(selected),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accentPrimary,
                  ),
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shell == null || !mounted) {
      return;
    }
    await ref.read(terminalsProvider.notifier).createSession(shell: shell);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final state = ref.watch(terminalsProvider);
    final active = state.activeSession;
    final transcript = state.transcript;

    ref.listen(
      terminalsProvider.select((s) => s.transcript.length + (s.executing ? 1 : 0)),
      (prev, next) {
        if (next != prev) {
          _scrollToEnd();
        }
      },
    );

    ref.listen(
      terminalsProvider.select((s) => s.executing),
      (prev, next) {
        if (prev == true && next == false) {
          _ensureInputFocused();
        }
      },
    );

    return ColoredBox(
      color: colors.chrome,
      child: Column(
        children: [
          _SessionBar(
            sessions: state.sessions,
            activeId: state.activeId,
            attached: state.attached,
            onCreate: _promptCreateTerminal,
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
            child: ColoredBox(
              color: _terminalBg,
              child: transcript.isEmpty
                  ? Center(
                      child: Text(
                        state.loading
                            ? 'Loading terminal…'
                            : state.attached
                                ? 'Ready.'
                                : 'Connect a terminal to begin.',
                        style: workbenchMonoStyle(
                          context,
                          size: 13,
                          color: colors.fgMuted,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: SelectableText(
                        state.executing ? '$transcript▌' : transcript,
                        style: workbenchMonoStyle(
                          context,
                          size: 13,
                          color: _terminalFg,
                        ),
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
                        : state.executing
                            ? '${active.name} · running…'
                            : '${active.name} · ${state.shell ?? active.shell}${state.pid != null ? ' · pid ${state.pid}' : ''}',
                    style: TextStyle(color: colors.fgMuted, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (state.executing)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.accentPrimary,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            color: colors.elevated,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    focusNode: _inputFocus,
                    enabled: state.attached,
                    readOnly: state.executing,
                    minLines: 1,
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                    style: workbenchMonoStyle(context, size: 13),
                    decoration: InputDecoration(
                      hintText: state.attached
                          ? 'Command… (tap ✓ to run)'
                          : 'Connect a terminal to type…',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
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
                    textInputAction: TextInputAction.none,
                    onSubmitted: (_) => _submitCommand(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed:
                      state.attached && !state.executing ? _submitCommand : null,
                  icon: const Icon(Icons.check, size: 22),
                  color: colors.accentPrimary,
                  tooltip: 'Send command',
                  style: IconButton.styleFrom(
                    backgroundColor: colors.input,
                    disabledBackgroundColor: colors.input,
                  ),
                ),
              ],
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
