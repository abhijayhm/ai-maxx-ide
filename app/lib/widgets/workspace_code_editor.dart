import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';

import '../core/files/code_language.dart';
import '../theme/workbench_colors.dart';
import '../theme/workbench_theme.dart';

/// Syntax-highlighted editor backed by
/// [flutter_code_editor](https://pub.dev/packages/flutter_code_editor).
class WorkspaceCodeEditor extends StatefulWidget {
  const WorkspaceCodeEditor({
    super.key,
    required this.source,
    required this.filePath,
    this.onChanged,
  });

  final String source;
  final String filePath;
  final ValueChanged<String>? onChanged;

  @override
  State<WorkspaceCodeEditor> createState() => _WorkspaceCodeEditorState();
}

class _WorkspaceCodeEditorState extends State<WorkspaceCodeEditor> {
  CodeController? _controller;
  String? _boundKey;

  @override
  void initState() {
    super.initState();
    _bindController();
  }

  @override
  void didUpdateWidget(covariant WorkspaceCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key = '${widget.filePath}\u0000${widget.source.length}';
    if (_boundKey != key && widget.source != _controller?.fullText) {
      _bindController();
    }
  }

  void _bindController() {
    _controller?.removeListener(_onTextChanged);
    _controller?.dispose();
    _controller = CodeController(
      text: widget.source,
      language: languageForPath(widget.filePath),
    )..addListener(_onTextChanged);
    _boundKey = '${widget.filePath}\u0000${widget.source.length}';
  }

  void _onTextChanged() {
    widget.onChanged?.call(_controller?.text ?? '');
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTextChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }

    final colors = context.workbenchColors;
    return ColoredBox(
      color: colors.canvas,
      child: CodeTheme(
        data: CodeThemeData(styles: atomOneDarkTheme),
        child: SingleChildScrollView(
          child: CodeField(
            controller: controller,
            textStyle: workbenchMonoStyle(context, size: 13),
            gutterStyle: GutterStyle(
              showErrors: true,
              showFoldingHandles: true,
              showLineNumbers: true,
              background: colors.app,
              textStyle: workbenchMonoStyle(
                context,
                size: 11,
                color: colors.fgInactive,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
