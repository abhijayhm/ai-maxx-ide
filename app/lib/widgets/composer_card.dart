import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/composer_settings_provider.dart';
import '../theme/workbench_colors.dart';

class ComposerCard extends ConsumerWidget {
  const ComposerCard({
    super.key,
    required this.controller,
    required this.onSend,
    this.onStop,
    this.running = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onStop;
  final bool running;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.workbenchColors;
    final settings = ref.watch(composerSettingsProvider);
    final settingsNotifier = ref.read(composerSettingsProvider.notifier);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.elevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(color: colors.fgDefault, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Plan, Build, / for skills, @ for context',
              hintStyle: TextStyle(color: colors.fgPlaceholder),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ModeButton(
                selected: settings.mode == ComposerAgentMode.agent,
                tooltip: 'Agent',
                onTap: () => settingsNotifier.setMode(ComposerAgentMode.agent),
                child: Text(
                  '∞',
                  style: TextStyle(
                    color: settings.mode == ComposerAgentMode.agent
                        ? colors.accentPrimary
                        : colors.fgMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _ModeButton(
                selected: settings.mode == ComposerAgentMode.plan,
                tooltip: 'Plan',
                onTap: () => settingsNotifier.setMode(ComposerAgentMode.plan),
                child: Icon(
                  Icons.sticky_note_2_outlined,
                  size: 16,
                  color: settings.mode == ComposerAgentMode.plan
                      ? Colors.amber.shade400
                      : colors.fgMuted,
                ),
              ),
              const SizedBox(width: 4),
              _ModeButton(
                selected: settings.mode == ComposerAgentMode.ask,
                tooltip: 'Ask',
                onTap: () => settingsNotifier.setMode(ComposerAgentMode.ask),
                child: Icon(
                  Icons.chat_bubble_outline,
                  size: 16,
                  color: settings.mode == ComposerAgentMode.ask
                      ? Colors.green.shade400
                      : colors.fgMuted,
                ),
              ),
              const SizedBox(width: 8),
              _ModelPicker(
                settings: settings,
                onSelected: settingsNotifier.setModel,
              ),
              const Spacer(),
              if (running && onStop != null)
                IconButton(
                  onPressed: onStop,
                  icon: Icon(Icons.stop, color: colors.statusError, size: 20),
                  tooltip: 'Stop agent',
                ),
              IconButton(
                onPressed: onSend,
                icon: Icon(Icons.send, color: colors.accentPrimary, size: 20),
                tooltip: 'Send',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.selected,
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? colors.input : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? colors.borderDefault : Colors.transparent,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ModelPicker extends StatelessWidget {
  const _ModelPicker({
    required this.settings,
    required this.onSelected,
  });

  final ComposerSettingsState settings;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final models = settings.models;
    final label = settings.modelsLoading
        ? 'Loading…'
        : (models
                .where((m) => m.id == settings.effectiveModelId)
                .map((m) => m.displayName)
                .firstOrNull ??
            settings.effectiveModelId);

    return PopupMenuButton<String>(
      tooltip: 'Model',
      onSelected: onSelected,
      itemBuilder: (context) {
        if (models.isEmpty) {
          return [
            PopupMenuItem(
              enabled: false,
              child: Text(
                settings.modelsLoading ? 'Loading models…' : 'No models',
                style: TextStyle(color: colors.fgMuted, fontSize: 12),
              ),
            ),
          ];
        }
        return models
            .map(
              (model) => PopupMenuItem<String>(
                value: model.id,
                child: Text(
                  model.displayName,
                  style: TextStyle(
                    color: model.id == settings.effectiveModelId
                        ? colors.accentPrimary
                        : colors.fgDefault,
                    fontSize: 12,
                  ),
                ),
              ),
            )
            .toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.input,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(color: colors.fgMuted, fontSize: 12),
            ),
            Icon(Icons.arrow_drop_down, size: 16, color: colors.fgMuted),
          ],
        ),
      ),
    );
  }
}
