import 'package:flutter/material.dart';

import '../core/sync/sync_models.dart';
import '../theme/workbench_colors.dart';

/// Sync status strip: spinner while indexing metadata, bar + % while loading files.
class SyncProgressBanner extends StatelessWidget {
  const SyncProgressBanner({
    super.key,
    required this.progress,
    this.compact = false,
  });

  final SyncProgress progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!progress.showBanner) {
      return const SizedBox.shrink();
    }

    final colors = context.workbenchColors;
    if (progress.hasError) {
      final message = progress.errorMessage ?? 'Sync failed';
      if (compact) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 14, color: colors.statusError),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'Sync failed',
                style: TextStyle(color: colors.statusError, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      }
      return Material(
        color: colors.elevated,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 18, color: colors.statusError),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: colors.statusError, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (progress.phase == SyncPhase.complete) {
      if (compact) {
        return Icon(Icons.check_circle_outline,
            size: 14, color: colors.statusSuccess);
      }
      return Material(
        color: colors.elevated,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Workspace synced',
            style: TextStyle(color: colors.statusSuccess, fontSize: 13),
          ),
        ),
      );
    }

    final percent = progress.filesProgressPercent;
    final fraction = progress.filesProgressFraction;
    final inFilesPhase = progress.phase == SyncPhase.files && percent != null;

    final label = inFilesPhase
        ? 'Syncing files $percent% (${progress.filesDone}/${progress.filesTotal})'
        : progress.statusLabel;

    final compactLabel = inFilesPhase
        ? '$percent%'
        : (progress.phase == SyncPhase.metadata ? 'Indexing…' : 'Sync…');

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: fraction,
              color: colors.accentPrimary,
              backgroundColor: colors.borderSubtle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            compactLabel,
            style: TextStyle(color: colors.fgMuted, fontSize: 11),
          ),
        ],
      );
    }

    return Material(
      color: colors.elevated,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.accentPrimary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: colors.fgDefault,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (inFilesPhase)
                  Text(
                    '$percent%',
                    style: TextStyle(
                      color: colors.accentPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            if (inFilesPhase) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 4,
                  backgroundColor: colors.borderSubtle,
                  color: colors.accentPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Centered loader for empty project search while sync runs.
class SyncProgressPanel extends StatelessWidget {
  const SyncProgressPanel({super.key, required this.progress});

  final SyncProgress progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final percent = progress.filesProgressPercent;
    final fraction = progress.filesProgressFraction;
    final inFilesPhase = progress.phase == SyncPhase.files && percent != null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                value: inFilesPhase ? fraction : null,
                color: colors.accentPrimary,
                backgroundColor: colors.borderSubtle,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              inFilesPhase
                  ? 'Syncing workspace files'
                  : 'Indexing workspace',
              style: TextStyle(
                color: colors.fgStrong,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              inFilesPhase
                  ? '$percent% complete · ${progress.filesDone} of ${progress.filesTotal} files'
                  : 'Building file tree from server…',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.fgMuted, fontSize: 13),
            ),
            if (inFilesPhase) ...[
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6,
                    backgroundColor: colors.borderSubtle,
                    color: colors.accentPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
