import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/files_repository.dart';
import 'app_providers.dart';

final filesRepositoryProvider = FutureProvider<FilesRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return FilesRepository(api);
});
