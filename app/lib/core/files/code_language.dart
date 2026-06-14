import 'package:highlight/highlight.dart' show Mode;
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/kotlin.dart';
import 'package:highlight/languages/markdown.dart';
import 'package:highlight/languages/php.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/rust.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/swift.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/yaml.dart';

/// Maps a workspace file path to a [highlight] language [Mode] for
/// [flutter_code_editor](https://pub.dev/packages/flutter_code_editor).
Mode? languageForPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) {
    return null;
  }
  switch (path.substring(dot + 1).toLowerCase()) {
    case 'dart':
      return dart;
    case 'py':
      return python;
    case 'js':
    case 'mjs':
    case 'cjs':
      return javascript;
    case 'ts':
    case 'tsx':
    case 'mts':
    case 'cts':
      return typescript;
    case 'jsx':
      return javascript;
    case 'json':
      return json;
    case 'md':
    case 'markdown':
      return markdown;
    case 'yaml':
    case 'yml':
      return yaml;
    case 'html':
    case 'htm':
    case 'xml':
    case 'svg':
      return xml;
    case 'css':
    case 'scss':
      return css;
    case 'sql':
      return sql;
    case 'sh':
    case 'bash':
    case 'zsh':
      return bash;
    case 'java':
      return java;
    case 'kt':
    case 'kts':
      return kotlin;
    case 'go':
      return go;
    case 'rs':
      return rust;
    case 'swift':
      return swift;
    case 'php':
      return php;
    default:
      return null;
  }
}

/// Language name string for [highlight.parse] / [HighlightView].
String? languageNameForPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) {
    return null;
  }
  switch (path.substring(dot + 1).toLowerCase()) {
    case 'dart':
      return 'dart';
    case 'py':
      return 'python';
    case 'js':
    case 'mjs':
    case 'cjs':
    case 'jsx':
      return 'javascript';
    case 'ts':
    case 'tsx':
    case 'mts':
    case 'cts':
      return 'typescript';
    case 'json':
      return 'json';
    case 'md':
    case 'markdown':
      return 'markdown';
    case 'yaml':
    case 'yml':
      return 'yaml';
    case 'html':
    case 'htm':
      return 'html';
    case 'xml':
    case 'svg':
      return 'xml';
    case 'css':
      return 'css';
    case 'scss':
      return 'scss';
    case 'sql':
      return 'sql';
    case 'sh':
    case 'bash':
    case 'zsh':
      return 'bash';
    case 'java':
      return 'java';
    case 'kt':
    case 'kts':
      return 'kotlin';
    case 'go':
      return 'go';
    case 'rs':
      return 'rust';
    case 'swift':
      return 'swift';
    case 'php':
      return 'php';
    default:
      return null;
  }
}
