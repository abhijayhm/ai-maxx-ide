import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_model.dart';
import 'agent_session_provider.dart';
import 'app_providers.dart';

enum ComposerAgentMode { agent, plan, ask }

class ComposerSettingsState {
  const ComposerSettingsState({
    this.mode = ComposerAgentMode.agent,
    this.selectedModelId,
    this.models = const [],
    this.modelsLoading = false,
    this.error,
  });

  final ComposerAgentMode mode;
  final String? selectedModelId;
  final List<AgentModelInfo> models;
  final bool modelsLoading;
  final String? error;

  String? get agentModeForSend {
    switch (mode) {
      case ComposerAgentMode.agent:
        return 'agent';
      case ComposerAgentMode.plan:
        return 'plan';
      case ComposerAgentMode.ask:
        return null;
    }
  }

  String get effectiveModelId =>
      selectedModelId ??
      (models.isNotEmpty ? models.first.id : 'composer-2.5');

  ComposerSettingsState copyWith({
    ComposerAgentMode? mode,
    String? selectedModelId,
    List<AgentModelInfo>? models,
    bool? modelsLoading,
    String? error,
    bool clearError = false,
  }) {
    return ComposerSettingsState(
      mode: mode ?? this.mode,
      selectedModelId: selectedModelId ?? this.selectedModelId,
      models: models ?? this.models,
      modelsLoading: modelsLoading ?? this.modelsLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final composerSettingsProvider =
    NotifierProvider<ComposerSettingsNotifier, ComposerSettingsState>(
  ComposerSettingsNotifier.new,
);

class ComposerSettingsNotifier extends Notifier<ComposerSettingsState> {
  bool _loaded = false;

  @override
  ComposerSettingsState build() {
    ref.listen(sessionProvider, (previous, next) {
      final wasReady = previous?.valueOrNull?.isReady ?? false;
      final isReady = next.valueOrNull?.isReady ?? false;
      if (!wasReady && isReady) {
        _loaded = false;
        Future.microtask(loadModels);
      }
    });
    Future.microtask(() {
      if (ref.read(sessionProvider).valueOrNull?.isReady ?? false) {
        loadModels();
      }
    });
    return const ComposerSettingsState(selectedModelId: 'composer-2.5');
  }

  Future<void> loadModels() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    state = state.copyWith(modelsLoading: true, clearError: true);
    try {
      final repo = await ref.read(agentRepositoryProvider.future);
      final models = await repo.fetchModels();
      state = state.copyWith(
        models: models,
        modelsLoading: false,
        selectedModelId: state.selectedModelId ??
            (models.isNotEmpty ? models.first.id : 'composer-2.5'),
      );
    } catch (error) {
      state = state.copyWith(
        modelsLoading: false,
        error: error.toString(),
        models: const [
          AgentModelInfo(id: 'composer-2.5', displayName: 'Composer 2.5'),
        ],
      );
    }
  }

  void setMode(ComposerAgentMode mode) {
    state = state.copyWith(mode: mode);
  }

  void setModel(String id) {
    state = state.copyWith(selectedModelId: id);
  }
}
