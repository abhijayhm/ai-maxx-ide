import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/agent_model.dart';
import 'agent_session_provider.dart';
import 'app_providers.dart';

const kAutoModelId = 'auto';

enum ComposerAgentMode { agent, plan }

class ComposerSettingsState {
  const ComposerSettingsState({
    this.mode = ComposerAgentMode.agent,
    this.selectedModelId = kAutoModelId,
    this.models = const [],
    this.modelsLoading = false,
    this.error,
  });

  final ComposerAgentMode mode;
  final String selectedModelId;
  final List<AgentModelInfo> models;
  final bool modelsLoading;
  final String? error;

  String get agentModeForSend => mode.name;

  /// Null means let the SDK pick (Auto).
  String? get modelForSend =>
      selectedModelId == kAutoModelId ? null : selectedModelId;

  String get displayModelLabel {
    if (selectedModelId == kAutoModelId) {
      return 'Auto';
    }
    for (final model in models) {
      if (model.id == selectedModelId) {
        return model.displayName;
      }
    }
    return selectedModelId;
  }

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
    return const ComposerSettingsState();
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
      state = state.copyWith(models: models, modelsLoading: false);
    } catch (error) {
      state = state.copyWith(
        modelsLoading: false,
        error: error.toString(),
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
