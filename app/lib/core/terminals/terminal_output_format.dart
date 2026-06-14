import 'terminal_output_sanitizer.dart';

/// Plain shell response for the grey output box (no JSON wrapper).
String formatTerminalStdout(String raw, String command) {
  var text = sanitizeTerminalOutput(raw);
  if (text.isEmpty) {
    return '';
  }

  final cmd = command.trim();
  if (cmd.isNotEmpty) {
    for (final prefix in [cmd, '$cmd\r\n', '$cmd\n', '$cmd\r']) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length);
        break;
      }
    }
  }

  final lines = text.split('\n');

  while (lines.isNotEmpty) {
    final first = lines.first.trim();
    if (first.isEmpty) {
      lines.removeAt(0);
      continue;
    }
    if (cmd.isNotEmpty && _lineMatchesCommand(first, cmd)) {
      lines.removeAt(0);
      continue;
    }
    break;
  }

  while (lines.isNotEmpty) {
    final last = lines.last.trimRight();
    if (last.isEmpty || _isShellPrompt(last.trim())) {
      lines.removeLast();
      continue;
    }
    break;
  }

  return lines.join('\n').trim();
}

bool _lineMatchesCommand(String line, String command) {
  if (line == command) {
    return true;
  }
  return line.toLowerCase() == command.toLowerCase();
}

bool _isShellPrompt(String line) {
  if (line.isEmpty) {
    return false;
  }
  return RegExp(
    r'^(PS [^\n>]+>\s*|>>\s*|(?:[A-Za-z]:)?\\[^\n>]*>\s*|>\s*)$',
  ).hasMatch(line);
}
