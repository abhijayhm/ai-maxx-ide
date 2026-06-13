import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/search_repository.dart';
import 'app_providers.dart';

final searchRepositoryProvider = FutureProvider<SearchRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return SearchRepository(api);
});

final grepSearchProvider =
    FutureProvider.family<List<GrepHit>, String>((ref, query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return const [];
  }
  final repo = await ref.watch(searchRepositoryProvider.future);
  return repo.grep(trimmed);
});

final serverFileSearchProvider =
    FutureProvider.family<List<ServerFileHit>, String>((ref, query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) {
    return const [];
  }
  final repo = await ref.watch(searchRepositoryProvider.future);
  return repo.searchFiles(trimmed);
});
