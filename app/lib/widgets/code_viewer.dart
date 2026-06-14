import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/files/code_language.dart';
import '../core/files/syntax_highlighter.dart';
import '../theme/workbench_theme.dart';

// ─── Design Tokens ───────────────────────────────────────────────────────────

class _C {
  static const bgApp = Color(0xFF181818);
  static const bgCanvas = Color(0xFF1F1F1F);

  static const borderSubtle = Color(0xFF2B2B2B);

  static const fgStrong = Color(0xFFFFFFFF);
  static const fgMuted = Color(0xFF9D9D9D);

  static const accentPrimary = Color(0xFF0078D4);

  static const selectionBg = Color(0x302488DB);
  static const searchMatch = Color(0x66B58900);
  static const searchMatchActive = Color(0x99E3B341);
}

typedef SelectionCallback = void Function(int startLine, int endLine);

/// Read-only code viewer with syntax highlighting, in-file search, and
/// long-press line-range selection (line numbers hidden).
class CodeViewer extends StatefulWidget {
  const CodeViewer({
    super.key,
    required this.source,
    this.filePath,
    this.fileName = 'file',
    this.onSelection,
    this.onBack,
    this.onEnterEdit,
    this.wrapLines = false,
    this.showHeader = true,
  });

  final String source;
  final String? filePath;
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
  static const _lineHeight = 22.0;

  late List<String> _lines;
  late List<List<TextSpan>> _syntaxSpans;

  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  int? _selStart;
  int? _selEnd;

  String _searchQuery = '';
  List<InFileSearchMatch> _searchMatches = const [];
  int _searchIndex = 0;

  bool get _hasSelection => _selStart != null;

  @override
  void initState() {
    super.initState();
    _rebuildLines();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CodeViewer old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source || old.filePath != widget.filePath) {
      _rebuildLines();
      _clearSelection();
      _refreshSearch();
    }
  }

  void _rebuildLines() {
    _lines = widget.source.split('\n');
    final languageName = languageNameForPath(widget.filePath ?? widget.fileName);
    _syntaxSpans = buildSyntaxLineSpans(widget.source, languageName);
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _searchMatches = findInFileMatches(_lines, _searchQuery);
      _searchIndex = 0;
    });
    if (_searchMatches.isNotEmpty) {
      _jumpToMatch(0);
    }
  }

  void _refreshSearch() {
    _searchMatches = findInFileMatches(_lines, _searchQuery);
    if (_searchIndex >= _searchMatches.length) {
      _searchIndex = 0;
    }
  }

  void _jumpToMatch(int index) {
    if (_searchMatches.isEmpty) {
      return;
    }
    final match = _searchMatches[index];
    final offset = (match.line - 1) * _lineHeight;
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _nextMatch() {
    if (_searchMatches.isEmpty) {
      return;
    }
    setState(() {
      _searchIndex = (_searchIndex + 1) % _searchMatches.length;
    });
    _jumpToMatch(_searchIndex);
  }

  void _prevMatch() {
    if (_searchMatches.isEmpty) {
      return;
    }
    setState(() {
      _searchIndex =
          (_searchIndex - 1 + _searchMatches.length) % _searchMatches.length;
    });
    _jumpToMatch(_searchIndex);
  }

  void _preserveScroll(void Function() update) {
    final offset =
        _scrollController.hasClients ? _scrollController.offset : null;
    update();
    if (offset == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    });
  }

  void _clearSelection() => _preserveScroll(() {
        setState(() {
          _selStart = null;
          _selEnd = null;
        });
      });

  void _handleLongPress(int line1Based) {
    _preserveScroll(() {
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

  int? _activeSearchStartForLine(int line1Based) {
    if (_searchMatches.isEmpty || _searchIndex >= _searchMatches.length) {
      return null;
    }
    final active = _searchMatches[_searchIndex];
    return active.line == line1Based ? active.start : null;
  }

  void _confirmSelection() {
    final s = _selStart!;
    final e = _selEnd ?? s;
    final lo = s < e ? s : e;
    final hi = s < e ? e : s;
    widget.onSelection?.call(lo, hi);
    _clearSelection();
  }

  void _selectAll() {
    if (_lines.isEmpty) {
      return;
    }
    _preserveScroll(() {
      setState(() {
        _selStart = 1;
        _selEnd = _lines.length;
      });
    });
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _C.bgApp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showHeader) ...[
            _Header(
              fileName: widget.fileName,
              hasSelection: _hasSelection,
              selStart: _selStart,
              selEnd: _selEnd,
              onConfirm: _confirmSelection,
              onClear: _clearSelection,
              onBack: widget.onBack,
              onEnterEdit: widget.onEnterEdit,
              onSelectAll: _lines.isNotEmpty && widget.onSelection != null
                  ? _selectAll
                  : null,
            ),
            Visibility(
              visible: !_hasSelection,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              child: _InFileSearchBar(
                controller: _searchController,
                matchCount: _searchMatches.length,
                matchIndex: _searchIndex,
                onPrev: _prevMatch,
                onNext: _nextMatch,
              ),
            ),
            const Divider(height: 1, thickness: 1, color: _C.borderSubtle),
          ],
          Expanded(
            child: ColoredBox(
              color: _C.bgCanvas,
              child: Stack(
                children: [
                  ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    itemCount: _lines.length,
                    itemBuilder: (ctx, i) {
                      final line1 = i + 1;
                      final syntax = i < _syntaxSpans.length
                          ? _syntaxSpans[i]
                          : [TextSpan(text: _lines[i])];
                      final highlighted = applySearchHighlights(
                        syntax,
                        _lines[i],
                        _searchQuery,
                        activeMatchStart: _activeSearchStartForLine(line1),
                        matchColor: _C.searchMatch,
                        activeMatchColor: _C.searchMatchActive,
                      );
                      return _CodeLine(
                        spans: highlighted,
                        isSelected: _isSelected(line1),
                        wrap: widget.wrapLines,
                        inSelectionMode: _hasSelection,
                        onLongPress: () => _handleLongPress(line1),
                        onTap: () => _handleTap(line1),
                      );
                    },
                  ),
                  if (_hasSelection)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _SelectionStatusBar(
                        start: _selStart!,
                        end: _selEnd,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InFileSearchBar extends StatelessWidget {
  const _InFileSearchBar({
    required this.controller,
    required this.matchCount,
    required this.matchIndex,
    required this.onPrev,
    required this.onNext,
  });

  final TextEditingController controller;
  final int matchCount;
  final int matchIndex;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final label = matchCount == 0
        ? '0/0'
        : '${matchIndex + 1}/$matchCount';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: workbenchMonoStyle(context, size: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Find in file',
                hintStyle: workbenchMonoStyle(
                  context,
                  size: 12,
                  color: _C.fgMuted,
                ),
                filled: true,
                fillColor: const Color(0xFF313131),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFF3C3C3C)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Color(0xFF3C3C3C)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11, color: _C.fgMuted)),
          _IconBtn(
            icon: Icons.keyboard_arrow_up,
            onTap: onPrev,
            tooltip: 'Previous match',
          ),
          _IconBtn(
            icon: Icons.keyboard_arrow_down,
            onTap: onNext,
            tooltip: 'Next match',
          ),
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
    this.onSelectAll,
  });

  final String fileName;
  final bool hasSelection;
  final int? selStart;
  final int? selEnd;
  final VoidCallback onConfirm;
  final VoidCallback onClear;
  final VoidCallback? onBack;
  final VoidCallback? onEnterEdit;
  final VoidCallback? onSelectAll;

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
                        ? 'Line $selStart — tap end line'
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
              tooltip: 'Add to composer',
              color: _C.accentPrimary,
            )
          else if (!hasSelection) ...[
            if (onSelectAll != null)
              _IconBtn(
                icon: Icons.select_all,
                onTap: onSelectAll!,
                tooltip: 'Select all lines',
              ),
            if (onEnterEdit != null)
              _IconBtn(
                icon: Icons.edit_outlined,
                onTap: onEnterEdit!,
                tooltip: 'Edit mode',
              ),
          ],
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
    required this.spans,
    required this.isSelected,
    required this.wrap,
    required this.inSelectionMode,
    required this.onLongPress,
    required this.onTap,
  });

  final List<InlineSpan> spans;
  final bool isSelected;
  final bool wrap;
  final bool inSelectionMode;
  final VoidCallback onLongPress;
  final VoidCallback onTap;

  static const _lineHeight = 22.0;

  @override
  Widget build(BuildContext context) {
    final leftBorder = isSelected
        ? const Border(left: BorderSide(color: _C.accentPrimary, width: 2))
        : null;

    final rich = RichText(
      text: TextSpan(children: spans),
      softWrap: wrap,
      overflow: wrap ? TextOverflow.visible : TextOverflow.clip,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      onTap: inSelectionMode ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        constraints: const BoxConstraints(minHeight: _lineHeight),
        decoration: BoxDecoration(
          color: isSelected ? _C.selectionBg : Colors.transparent,
          border: leftBorder,
        ),
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: wrap
            ? rich
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: rich,
              ),
      ),
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
        ? 'Long-press another line to set the end'
        : 'Tap ✓ to add @path:$start-$end to composer';

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
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: _C.fgMuted),
              overflow: TextOverflow.ellipsis,
            ),
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
          filePath: widget.filePath,
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
