import 'package:flutter_test/flutter_test.dart';

import 'package:ai_maxx_ide/core/sync/sync_models.dart';

void main() {
  test('SyncProgress filesProgressPercent', () {
    const progress = SyncProgress(
      phase: SyncPhase.files,
      filesTotal: 100,
      filesDone: 42,
    );
    expect(progress.filesProgressPercent, 42);
    expect(progress.filesProgressFraction, closeTo(0.42, 0.001));
  });

  test('SyncProgress statusLabel during files phase', () {
    const progress = SyncProgress(
      phase: SyncPhase.files,
      filesTotal: 10,
      filesDone: 3,
    );
    expect(progress.statusLabel, 'Syncing files 3/10');
  });
}
