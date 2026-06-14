import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_file_view/in_app_file_view.dart';
import 'package:path_provider/path_provider.dart';

import '../core/files/file_viewer_extensions.dart';
import '../core/providers/ide_file_provider.dart';
import '../theme/workbench_colors.dart';
import '../theme/workbench_theme.dart';
import 'code_viewer.dart';
import 'workspace_code_editor.dart';

class WorkspaceFileViewer extends StatefulWidget {
  const WorkspaceFileViewer({
    super.key,
    required this.file,
    required this.onClose,
    required this.onPickRange,
    this.editMode = false,
  });

  final OpenFileState file;
  final VoidCallback onClose;
  final void Function(String contextRef) onPickRange;

  /// When false (default), shows read-only [CodeViewer] with line selection.
  /// When true, shows syntax-highlighted [WorkspaceCodeEditor].
  final bool editMode;

  @override
  State<WorkspaceFileViewer> createState() => _WorkspaceFileViewerState();
}

class _WorkspaceFileViewerState extends State<WorkspaceFileViewer> {
  late bool _editMode;
  String? _binaryTempPath;
  FileViewController? _fileViewController;

  @override
  void initState() {
    super.initState();
    _editMode = widget.editMode;
  }

  @override
  void dispose() {
    _fileViewController?.dispose();
    _deleteTempFile();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WorkspaceFileViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      _deleteTempFile();
      _editMode = widget.editMode;
    }
    if (!widget.file.loading &&
        widget.file.bytes != null &&
        isInAppFileViewPath(widget.file.path ?? '')) {
      _ensureBinaryTempFile();
    }
  }

  bool get _isImagePath {
    final path = (widget.file.path ?? '').toLowerCase();
    return path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.gif') ||
        path.endsWith('.webp') ||
        path.endsWith('.bmp') ||
        path.endsWith('.heic');
  }

  Future<void> _ensureBinaryTempFile() async {
    if (_binaryTempPath != null || widget.file.bytes == null) {
      return;
    }
    final dir = await getTemporaryDirectory();
    final name = widget.file.asset ?? 'preview';
    final file = File('${dir.path}/aimaxx_preview_$name');
    await file.writeAsBytes(widget.file.bytes!, flush: true);
    if (!mounted) {
      return;
    }
    setState(() {
      _binaryTempPath = file.path;
      _fileViewController?.dispose();
      _fileViewController = FileViewController.file(file);
    });
  }

  Future<void> _deleteTempFile() async {
    final path = _binaryTempPath;
    _binaryTempPath = null;
    if (path == null) {
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  void _onSelection(int start, int end) {
    final path = widget.file.path;
    if (path == null) {
      return;
    }
    widget.onPickRange('@$path:$start-$end');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    final file = widget.file;
    final isTextCode = !isInAppFileViewPath(file.path ?? '');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.elevated,
        border: Border(
          top: BorderSide(color: colors.borderDefault),
          bottom: BorderSide(color: colors.borderSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isTextCode && !file.loading && file.error == null && _editMode)
            _Toolbar(
              fileName: file.asset ?? file.path ?? 'File',
              onToggleEdit: () => setState(() => _editMode = false),
              onClose: widget.onClose,
            ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final colors = context.workbenchColors;
    final file = widget.file;

    if (file.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (file.error != null) {
      return Center(
        child: Text(
          file.error!,
          style: TextStyle(color: colors.statusError, fontSize: 12),
        ),
      );
    }

    final path = file.path ?? '';
    if (isInAppFileViewPath(path)) {
      return _buildInAppViewer(context);
    }

    final source = file.textContent ?? '';
    if (source.isEmpty) {
      return Center(
        child: Text(
          'File is empty.',
          style: TextStyle(color: colors.fgMuted, fontSize: 13),
        ),
      );
    }

    if (_editMode) {
      return WorkspaceCodeEditor(
        source: source,
        filePath: path,
      );
    }

    return CodeViewer(
      source: source,
      fileName: file.asset ?? path,
      onSelection: _onSelection,
      onBack: widget.onClose,
      onEnterEdit: () => setState(() => _editMode = true),
      showHeader: true,
    );
  }

  Widget _buildInAppViewer(BuildContext context) {
    final colors = context.workbenchColors;
    final tempPath = _binaryTempPath;
    if (tempPath == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!kIsWeb && Platform.isIOS && _fileViewController != null) {
      return FileView(controller: _fileViewController!);
    }

    if (_isImagePath && widget.file.bytes != null) {
      return InteractiveViewer(
        child: Center(
          child: Image.memory(
            widget.file.bytes!,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => Text(
              'Unable to preview image.',
              style: TextStyle(color: colors.statusError, fontSize: 12),
            ),
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Preview for this file type is available on iOS via in-app viewer.\n$tempPath',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.fgMuted, fontSize: 12),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.fileName,
    required this.onToggleEdit,
    required this.onClose,
  });

  final String fileName;
  final VoidCallback onToggleEdit;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.workbenchColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              fileName,
              style: workbenchMonoStyle(context, size: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: onToggleEdit,
            icon: Icon(Icons.visibility_outlined, size: 20),
            color: colors.accentPrimary,
            tooltip: 'View mode',
          ),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close, color: colors.fgMuted, size: 20),
            tooltip: 'Close file',
          ),
        ],
      ),
    );
  }
}
