import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:highlight/highlight.dart' show Node, highlight;

import '../../theme/workbench_theme.dart';

/// Builds per-line syntax-highlighted [TextSpan]s using atom-one-dark.
List<List<TextSpan>> buildSyntaxLineSpans(
  String source,
  String? languageName, {
  TextStyle? baseStyle,
}) {
  final style = baseStyle ?? vscodeEditorTextStyleRaw();
  final theme = atomOneDarkTheme.map(
    (key, value) => MapEntry(key, style.merge(value)),
  );
  final lines = source.split('\n');

  if (languageName == null) {
    return lines
        .map(
          (line) => [
            TextSpan(text: line.isEmpty ? ' ' : line, style: style),
          ],
        )
        .toList();
  }

  return lines
      .map((line) => _highlightLine(line, languageName, theme, style))
      .toList();
}

List<TextSpan> _highlightLine(
  String line,
  String languageName,
  Map<String, TextStyle> theme,
  TextStyle fallback,
) {
  if (line.isEmpty) {
    return [TextSpan(text: ' ', style: fallback)];
  }
  final nodes = highlight.parse(line, language: languageName).nodes;
  if (nodes == null || nodes.isEmpty) {
    return [TextSpan(text: line, style: fallback)];
  }
  final spans = _nodesToSpans(nodes, theme, fallback);
  return spans.isEmpty ? [TextSpan(text: line, style: fallback)] : spans;
}

List<TextSpan> _nodesToSpans(
  List<Node> nodes,
  Map<String, TextStyle> theme,
  TextStyle fallback,
) {
  final spans = <TextSpan>[];

  void walk(Node node, TextStyle inherited) {
    final style = node.className != null && theme.containsKey(node.className)
        ? theme[node.className!]!
        : inherited;
    if (node.value != null && node.value!.isNotEmpty) {
      spans.add(TextSpan(text: node.value, style: style));
      return;
    }
    for (final child in node.children ?? const <Node>[]) {
      walk(child, style);
    }
  }

  for (final node in nodes) {
    walk(node, fallback);
  }
  return spans;
}

/// Merges in-file search match highlights onto syntax spans.
List<InlineSpan> applySearchHighlights(
  List<TextSpan> syntaxSpans,
  String lineText,
  String query, {
  required int? activeMatchStart,
  required Color matchColor,
  required Color activeMatchColor,
}) {
  if (query.isEmpty) {
    return syntaxSpans;
  }

  final plain = lineText;
  final haystack = plain.toLowerCase();
  final needle = query.toLowerCase();
  if (!haystack.contains(needle)) {
    return syntaxSpans;
  }

  final baseStyle = syntaxSpans.isNotEmpty
      ? (syntaxSpans.first.style ?? const TextStyle(fontSize: 13))
      : const TextStyle(fontSize: 13);
  final output = <InlineSpan>[];
  var cursor = 0;

  while (cursor < plain.length) {
    final hit = haystack.indexOf(needle, cursor);
    if (hit < 0) {
      output.add(TextSpan(text: plain.substring(cursor), style: baseStyle));
      break;
    }
    if (hit > cursor) {
      output.add(TextSpan(text: plain.substring(cursor, hit), style: baseStyle));
    }
    final isActive = activeMatchStart != null && hit == activeMatchStart;
    output.add(
      TextSpan(
        text: plain.substring(hit, hit + needle.length),
        style: baseStyle.copyWith(
          backgroundColor: isActive ? activeMatchColor : matchColor,
          color: const Color(0xFFFFFFFF),
        ),
      ),
    );
    cursor = hit + needle.length;
  }

  return output.isEmpty ? syntaxSpans : output;
}

class InFileSearchMatch {
  const InFileSearchMatch({required this.line, required this.start});

  final int line;
  final int start;
}

List<InFileSearchMatch> findInFileMatches(List<String> lines, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return const [];
  }
  final hits = <InFileSearchMatch>[];
  for (var i = 0; i < lines.length; i++) {
    final haystack = lines[i].toLowerCase();
    var from = 0;
    while (true) {
      final idx = haystack.indexOf(needle, from);
      if (idx < 0) {
        break;
      }
      hits.add(InFileSearchMatch(line: i + 1, start: idx));
      from = idx + needle.length;
    }
  }
  return hits;
}
