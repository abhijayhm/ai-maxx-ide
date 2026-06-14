import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory projects tab browse state (search + tree) survives file open/close.
class ProjectsBrowseState {
  const ProjectsBrowseState({
    this.query = '',
    this.searchMode = 0,
    this.matchCase = false,
    this.matchWholeWord = false,
  });

  final String query;
  final int searchMode;
  final bool matchCase;
  final bool matchWholeWord;

  bool get isSearching => query.trim().isNotEmpty;

  ProjectsBrowseState copyWith({
    String? query,
    int? searchMode,
    bool? matchCase,
    bool? matchWholeWord,
  }) {
    return ProjectsBrowseState(
      query: query ?? this.query,
      searchMode: searchMode ?? this.searchMode,
      matchCase: matchCase ?? this.matchCase,
      matchWholeWord: matchWholeWord ?? this.matchWholeWord,
    );
  }
}

final projectsBrowseProvider =
    NotifierProvider<ProjectsBrowseNotifier, ProjectsBrowseState>(
  ProjectsBrowseNotifier.new,
);

class ProjectsBrowseNotifier extends Notifier<ProjectsBrowseState> {
  @override
  ProjectsBrowseState build() => const ProjectsBrowseState();

  void setQuery(String query) {
    state = state.copyWith(query: query);
  }

  void setSearchMode(int mode) {
    state = state.copyWith(searchMode: mode);
  }

  void setMatchCase(bool value) {
    state = state.copyWith(matchCase: value);
  }

  void setMatchWholeWord(bool value) {
    state = state.copyWith(matchWholeWord: value);
  }

  void clearQuery() {
    state = state.copyWith(query: '');
  }
}
