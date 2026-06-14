/// Cleans raw PTY output for display (Windows shells emit ANSI/OSC noise).
String sanitizeTerminalOutput(String raw) {
  var text = raw;

  // CSI sequences — colors, cursor, erase, etc.
  text = text.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
  // OSC sequences — titles, prompts, etc.
  text = text.replaceAll(RegExp(r'\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)'), '');
  // Single-byte ESC leftovers and DEC private modes.
  text = text.replaceAll(RegExp(r'\x1B[()][A-Z0-9]'), '');
  text = text.replaceAll(RegExp(r'\x1B[>=]'), '');
  // BEL / backspace artifacts sometimes shown as replacement chars.
  text = text.replaceAll('\x07', '');
  // Normalize Windows line endings.
  text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  return text;
}
