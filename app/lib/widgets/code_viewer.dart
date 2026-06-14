import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/workbench_theme.dart';

// ─── Design Tokens ───────────────────────────────────────────────────────────

class _C {
  static const bgApp = Color(0xFF181818);
  static const bgCanvas = Color(0xFF1F1F1F);
  static const bgElevated = Color(0xFF222222);
  static const bgInput = Color(0xFF313131);

  static const borderSubtle = Color(0xFF2B2B2B);
  static const borderDefault = Color(0xFF3C3C3C);

  static const fgDefault = Color(0xFFCCCCCC);
  static const fgStrong = Color(0xFFFFFFFF);
  static const fgMuted = Color(0xFF9D9D9D);
  static const fgInactive = Color(0xFF6E7681);

  static const accentPrimary = Color(0xFF0078D4);
  static const accentSecondaryAlpha = Color(0x402488DB);

  static const selectionBg = Color(0x302488DB);
  static const selectionBorder = Color(0xFF2488DB);
}

typedef SelectionCallback = void Function(int startLine, int endLine);

/// VS Code-style read-only code viewer with line-range selection.
///
/// Long-press a line to start selection, long-press (or tap) another line for
/// the end, then tap ✓ to fire [onSelection].
class CodeViewer extends StatefulWidget {
  const CodeViewer({
    super.key,
    required this.source,
    this.fileName = 'file',
    this.onSelection,
    this.onBack,
    this.onEnterEdit,
    this.wrapLines = false,
    this.showHeader = true,
  });

  final String source;
  final String fileName;
  final SelectionCallback? onSelection;
  final VoidCallback? onBack;
  final VoidCallback? onEnterEdit;
  final bool wrapLines;
  final bool showHeader;

  @override
  State<CodeViewer> createState() => _CodeViewerState();
}

class _CodeViewerState extends State<CodeViewer> {
  late List<String> _lines;

  int? _selStart;
  int? _selEnd;

  bool get _hasSelection => _selStart != null;

  @override
  void initState() {
    super.initState();
    _lines = widget.source.split('\n');
  }

  @override
  void didUpdateWidget(CodeViewer old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) {
      _lines = widget.source.split('\n');
      _clearSelection();
    }
  }

  void _clearSelection() => setState(() {
        _selStart = null;
        _selEnd = null;
      });

  void _handleLongPress(int line1Based) {
    setState(() {
      if (_selStart == null) {
        _selStart = line1Based;
        _selEnd = null;
      } else if (_selEnd == null) {
        if (line1Based < _selStart!) {
          _selEnd = _selStart;
          _selStart = line1Based;
        } else {
          _selEnd = line1Based;
        }
      } else {
        _selStart = line1Based;
        _selEnd = null;
      }
    });

    HapticFeedback.selectionClick();
  }

  void _handleTap(int line1Based) {
    if (!_hasSelection) {
      return;
    }
    _handleLongPress(line1Based);
  }

  bool _isSelected(int line1Based) {
    if (_selStart == null) {
      return false;
    }
    final end = _selEnd ?? _selStart!;
    final lo = _selStart! < end ? _selStart! : end;
    final hi = _selStart! < end ? end : _selStart!;
    return line1Based >= lo && line1Based <= hi;
  }

  void _confirmSelection() {
    final s = _selStart!;
    final e = _selEnd ?? s;
    final lo = s < e ? s : e;
    final hi = s < e ? e : s;
    widget.onSelection?.call(lo, hi);
    _clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _C.bgApp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showHeader)
            _Header(
              fileName: widget.fileName,
              hasSelection: _hasSelection,
              selStart: _selStart,
              selEnd: _selEnd,
              onConfirm: _confirmSelection,
              onClear: _clearSelection,
              onBack: widget.onBack,
              onEnterEdit: widget.onEnterEdit,
            ),
          if (widget.showHeader)
            const Divider(height: 1, thickness: 1, color: _C.borderSubtle),
          Expanded(
            child: ColoredBox(
              color: _C.bgCanvas,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _lines.length,
                itemBuilder: (ctx, i) {
                  final line1 = i + 1;
                  return _CodeLine(
                    lineNumber: line1,
                    text: _lines[i],
                    isSelected: _isSelected(line1),
                    wrap: widget.wrapLines,
                    inSelectionMode: _hasSelection,
                    onLongPress: () => _handleLongPress(line1),
                    onTap: () => _handleTap(line1),
                    monoStyle: workbenchMonoStyle(ctx, size: 13),
                    gutterStyle: workbenchMonoStyle(
                      ctx,
                      size: 13,
                      color: _isSelected(line1) ? _C.fgDefault : _C.fgInactive,
                    ),
                  );
                },
              ),
            ),
          ),
          if (_hasSelection) _SelectionStatusBar(start: _selStart!, end: _selEnd),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.fileName,
    required this.hasSelection,
    required this.selStart,
    required this.selEnd,
    required this.onConfirm,
    required this.onClear,
    this.onBack,
    this.onEnterEdit,
  });

  final String fileName;
  final bool hasSelection;
  final int? selStart;
  final int? selEnd;
  final VoidCallback onConfirm;
  final VoidCallback onClear;
  final VoidCallback? onBack;
  final VoidCallback? onEnterEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      color: _C.bgApp,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          _IconBtn(
            icon: hasSelection ? Icons.close : Icons.arrow_back,
            onTap: hasSelection ? onClear : (onBack ?? () {}),
            tooltip: hasSelection ? 'Cancel selection' : 'Back',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: hasSelection
                ? Text(
                    selEnd == null
                        ? 'Line $selStart selected — tap end line'
                        : 'Lines $selStart to $selEnd',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _C.fgStrong,
                    ),
                    overflow: TextOverflow.ellipsis,
                  )
                : Text(
                    fileName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _C.fgStrong,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          if (hasSelection && selEnd != null)
            _IconBtn(
              icon: Icons.check,
              onTap: onConfirm,
              tooltip: 'Confirm selection',
              color: _C.accentPrimary,
            )
          else if (!hasSelection && onEnterEdit != null)
            _IconBtn(
              icon: Icons.edit_outlined,
              onTap: onEnterEdit!,
              tooltip: 'Edit mode',
            ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.color = _C.fgMuted,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

class _CodeLine extends StatelessWidget {
  const _CodeLine({
    required this.lineNumber,
    required this.text,
    required this.isSelected,
    required this.wrap,
    required this.inSelectionMode,
    required this.onLongPress,
    required this.onTap,
    required this.monoStyle,
    required this.gutterStyle,
  });

  final int lineNumber;
  final String text;
  final bool isSelected;
  final bool wrap;
  final bool inSelectionMode;
  final VoidCallback onLongPress;
  final VoidCallback onTap;
  final TextStyle monoStyle;
  final TextStyle gutterStyle;

  static const _gutterWidth = 44.0;
  static const _lineHeight = 22.0;

  @override
  Widget build(BuildContext context) {
    final leftBorder = isSelected
        ? const Border(left: BorderSide(color: _C.accentPrimary, width: 2))
        : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      onTap: inSelectionMode ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        decoration: BoxDecoration(
          color: isSelected ? _C.selectionBg : Colors.transparent,
          border: leftBorder,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _gutterWidth,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 2, bottom: 2),
                child: Text(
                  '$lineNumber',
                  textAlign: TextAlign.right,
                  style: gutterStyle.copyWith(height: _lineHeight / 13),
                ),
              ),
            ),
            Expanded(
              child: wrap
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: _CodeText(text: text, style: monoStyle),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: _CodeText(text: text, style: monoStyle),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeText extends StatelessWidget {
  const _CodeText({required this.text, required this.style});
  final String text;
  final TextStyle style;

  static const _lineHeight = 22.0;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.isEmpty ? ' ' : text,
      softWrap: false,
      style: style.copyWith(height: _lineHeight / 13),
    );
  }
}

class _SelectionStatusBar extends StatelessWidget {
  const _SelectionStatusBar({required this.start, required this.end});
  final int start;
  final int? end;

  @override
  Widget build(BuildContext context) {
    final label = end == null
        ? 'Tap another line to set end of selection'
        : 'Tap ✓ to confirm lines $start – $end';

    return Container(
      height: 28,
      color: _C.bgApp,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: _C.accentPrimary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: _C.fgMuted),
          ),
        ],
      ),
    );
  }
}

/// Loads a file from disk or asset, then shows [CodeViewer].
class FileCodeViewer extends StatefulWidget {
  const FileCodeViewer({
    super.key,
    this.filePath,
    this.assetPath,
    this.fileName,
    this.wrapLines = false,
    this.onSelection,
    this.onBack,
  }) : assert(filePath != null || assetPath != null,
            'Provide filePath or assetPath');

  final String? filePath;
  final String? assetPath;
  final String? fileName;
  final bool wrapLines;
  final SelectionCallback? onSelection;
  final VoidCallback? onBack;

  @override
  State<FileCodeViewer> createState() => _FileCodeViewerState();
}

class _FileCodeViewerState extends State<FileCodeViewer> {
  late Future<String> _contentFuture;

  @override
  void initState() {
    super.initState();
    _contentFuture = _load();
  }

  Future<String> _load() async {
    if (widget.filePath != null) {
      return File(widget.filePath!).readAsString();
    }
    return rootBundle.loadString(widget.assetPath!);
  }

  String get _displayName =>
      widget.fileName ??
      (widget.filePath != null
          ? widget.filePath!.split(Platform.pathSeparator).last
          : widget.assetPath!.split('/').last);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _contentFuture,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _LoadingShell();
        }
        if (snap.hasError) {
          return _ErrorShell(error: snap.error.toString());
        }
        return CodeViewer(
          source: snap.data!,
          fileName: _displayName,
          wrapLines: widget.wrapLines,
          onSelection: widget.onSelection,
          onBack: widget.onBack,
        );
      },
    );
  }
}

class _LoadingShell extends StatelessWidget {
  const _LoadingShell();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: _C.bgApp,
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: _C.accentPrimary,
        ),
      ),
    );
  }
}

class _ErrorShell extends StatelessWidget {
  const _ErrorShell({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _C.bgApp,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            'Failed to load file\n$error',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFFF85149)),
          ),
        ),
      ),
    );
  }
}
