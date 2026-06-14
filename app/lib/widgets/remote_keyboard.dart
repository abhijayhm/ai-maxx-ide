import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────

class _T {
  static const bgChrome = Color(0xFF181818);
  static const bgCanvas = Color(0xFF1F1F1F);
  static const bgElevated = Color(0xFF222222);
  static const bgInput = Color(0xFF313131);
  static const bgInputHov = Color(0xFF3C3C3C);
  static const borderSub = Color(0xFF2B2B2B);
  static const borderDef = Color(0xFF3C3C3C);
  static const fgDefault = Color(0xFFCCCCCC);
  static const fgStrong = Color(0xFFFFFFFF);
  static const fgMuted = Color(0xFF9D9D9D);
  static const fgInactive = Color(0xFF868686);
  static const accentPrim = Color(0xFF0078D4);
  static const statusErr = Color(0xFFF85149);
}

// ─── Key types ────────────────────────────────────────────────────────────────

enum _KeyRole { normal, action, accent, destructive, wide, spacer }

class _Key {
  const _Key(
    this.label, {
    this.sublabel,
    this.value,
    this.role = _KeyRole.normal,
    this.flex = 1,
  });

  final String label;
  final String? sublabel;
  final String? value;
  final _KeyRole role;
  final double flex;
}

enum KeyboardMode { text, numbers, special, fn }

const _textRows = [
  [
    _Key('q'),
    _Key('w'),
    _Key('e'),
    _Key('r'),
    _Key('t'),
    _Key('y'),
    _Key('u'),
    _Key('i'),
    _Key('o'),
    _Key('p'),
  ],
  [
    _Key('a'),
    _Key('s'),
    _Key('d'),
    _Key('f'),
    _Key('g'),
    _Key('h'),
    _Key('j'),
    _Key('k'),
    _Key('l'),
  ],
  [
    _Key('⇧', value: '__shift__', role: _KeyRole.action, flex: 1.4),
    _Key('z'),
    _Key('x'),
    _Key('c'),
    _Key('v'),
    _Key('b'),
    _Key('n'),
    _Key('m'),
    _Key('⌫', value: '__back__', role: _KeyRole.action, flex: 1.4),
  ],
  [
    _Key('123', value: '__mode_numbers__', role: _KeyRole.action, flex: 1.4),
    _Key(r'$#', value: '__mode_special__', role: _KeyRole.action, flex: 1.2),
    _Key('', value: '__space__', role: _KeyRole.wide, flex: 4.0),
    _Key('↵', value: '\n', role: _KeyRole.accent, flex: 1.4),
  ],
];

const _numRows = [
  [
    _Key('1'),
    _Key('2'),
    _Key('3'),
    _Key('4'),
    _Key('5'),
    _Key('6'),
    _Key('7'),
    _Key('8'),
    _Key('9'),
    _Key('0'),
  ],
  [
    _Key('-'),
    _Key('/'),
    _Key(':'),
    _Key(';'),
    _Key('('),
    _Key(')'),
    _Key(r'$'),
    _Key('&'),
    _Key('@'),
    _Key('"'),
  ],
  [
    _Key(r'$#', value: '__mode_special__', role: _KeyRole.action, flex: 1.4),
    _Key('.'),
    _Key(','),
    _Key('?'),
    _Key('!'),
    _Key("'"),
    _Key('⌫', value: '__back__', role: _KeyRole.action, flex: 1.4),
  ],
  [
    _Key('ABC', value: '__mode_text__', role: _KeyRole.action, flex: 1.4),
    _Key('Fn', value: '__mode_fn__', role: _KeyRole.action, flex: 1.2),
    _Key('', value: '__space__', role: _KeyRole.wide, flex: 4.0),
    _Key('↵', value: '\n', role: _KeyRole.accent, flex: 1.4),
  ],
];

const _specialRows = [
  [
    _Key('['),
    _Key(']'),
    _Key('{'),
    _Key('}'),
    _Key('#'),
    _Key('%'),
    _Key('^'),
    _Key('*'),
    _Key('+'),
    _Key('='),
  ],
  [
    _Key('_'),
    _Key(r'\'),
    _Key('|'),
    _Key('~'),
    _Key('<'),
    _Key('>'),
    _Key('€'),
    _Key('£'),
    _Key('¥'),
    _Key('•'),
  ],
  [
    _Key('123', value: '__mode_numbers__', role: _KeyRole.action, flex: 1.4),
    _Key('.'),
    _Key(','),
    _Key('?'),
    _Key('!'),
    _Key("'"),
    _Key('⌫', value: '__back__', role: _KeyRole.action, flex: 1.4),
  ],
  [
    _Key('ABC', value: '__mode_text__', role: _KeyRole.action, flex: 1.4),
    _Key('Fn', value: '__mode_fn__', role: _KeyRole.action, flex: 1.2),
    _Key('', value: '__space__', role: _KeyRole.wide, flex: 4.0),
    _Key('↵', value: '\n', role: _KeyRole.accent, flex: 1.4),
  ],
];

const _fnRows = [
  [
    _Key('Esc', value: '\x1b', role: _KeyRole.action, flex: 1.3),
    _Key('F1', value: '\x1bOP'),
    _Key('F2', value: '\x1bOQ'),
    _Key('F3', value: '\x1bOR'),
    _Key('F4', value: '\x1bOS'),
    _Key('F5', value: '\x1b[15~'),
    _Key('F6', value: '\x1b[17~'),
    _Key('F7', value: '\x1b[18~'),
    _Key('F8', value: '\x1b[19~'),
    _Key('F9', value: '\x1b[20~'),
  ],
  [
    _Key('F10', value: '\x1b[21~'),
    _Key('F11', value: '\x1b[23~'),
    _Key('F12', value: '\x1b[24~'),
    _Key('Del', value: '\x1b[3~', role: _KeyRole.destructive),
    _Key('Ins', value: '\x1b[2~'),
    _Key('Home', value: '\x1b[H'),
    _Key('End', value: '\x1b[F'),
    _Key('PgUp', value: '\x1b[5~'),
    _Key('PgDn', value: '\x1b[6~'),
    _Key('⌫', value: '__back__', role: _KeyRole.action),
  ],
  [
    _Key('Tab', value: '\t', role: _KeyRole.action, flex: 1.4),
    _Key('Caps', value: '__caps__', role: _KeyRole.action, flex: 1.2),
    _Key('⇧', value: '__shift__', role: _KeyRole.action, flex: 1.0),
    _Key('Ctrl', value: '__ctrl__', role: _KeyRole.action, flex: 1.0),
    _Key('Alt', value: '__alt__', role: _KeyRole.action, flex: 1.0),
    _Key('Meta', value: '__meta__', role: _KeyRole.action, flex: 1.0),
    _Key('↑', value: '\x1b[A', role: _KeyRole.action),
    _Key('↓', value: '\x1b[B', role: _KeyRole.action),
    _Key('←', value: '\x1b[D', role: _KeyRole.action),
    _Key('→', value: '\x1b[C', role: _KeyRole.action),
  ],
  [
    _Key('ABC', value: '__mode_text__', role: _KeyRole.action, flex: 1.4),
    _Key('123', value: '__mode_numbers__', role: _KeyRole.action, flex: 1.2),
    _Key('', value: '__space__', role: _KeyRole.wide, flex: 4.0),
    _Key('↵', value: '\n', role: _KeyRole.accent, flex: 1.4),
  ],
];

class RemoteKeyboardController extends ValueNotifier<RemoteKeyboardState> {
  RemoteKeyboardController() : super(const RemoteKeyboardState());

  void toggleMode(KeyboardMode m) {
    value = value.copyWith(mode: m);
  }

  void toggleShift() {
    value = value.copyWith(shift: !value.shift, sticky: false);
  }

  void toggleCaps() {
    value = value.copyWith(caps: !value.caps);
  }

  void toggleModifier(String mod) {
    final next = Set<String>.from(value.activeModifiers);
    if (next.contains(mod)) {
      next.remove(mod);
    } else {
      next.add(mod);
    }
    value = value.copyWith(activeModifiers: next);
  }

  String resolve(String raw) {
    var out = raw;
    if ((value.shift || value.caps) && raw.length == 1) {
      out = raw.toUpperCase();
    }
    if (value.shift && !value.sticky) {
      value = value.copyWith(shift: false);
    }
    return out;
  }
}

class RemoteKeyboardState {
  const RemoteKeyboardState({
    this.mode = KeyboardMode.text,
    this.shift = false,
    this.caps = false,
    this.sticky = false,
    this.activeModifiers = const {},
  });

  final KeyboardMode mode;
  final bool shift;
  final bool caps;
  final bool sticky;
  final Set<String> activeModifiers;

  RemoteKeyboardState copyWith({
    KeyboardMode? mode,
    bool? shift,
    bool? caps,
    bool? sticky,
    Set<String>? activeModifiers,
  }) =>
      RemoteKeyboardState(
        mode: mode ?? this.mode,
        shift: shift ?? this.shift,
        caps: caps ?? this.caps,
        sticky: sticky ?? this.sticky,
        activeModifiers: activeModifiers ?? this.activeModifiers,
      );
}

/// Custom on-screen keyboard for the Remote control tab.
class RemoteKeyboard extends StatefulWidget {
  const RemoteKeyboard({
    super.key,
    required this.onKey,
    this.controller,
    this.onModifiersChanged,
  });

  final void Function(String value, Set<String> modifiers) onKey;
  final RemoteKeyboardController? controller;
  final VoidCallback? onModifiersChanged;

  @override
  State<RemoteKeyboard> createState() => _RemoteKeyboardState();
}

class _RemoteKeyboardState extends State<RemoteKeyboard> {
  late final RemoteKeyboardController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? RemoteKeyboardController();
    _ctrl.addListener(_onCtrlChanged);
  }

  void _onCtrlChanged() {
    setState(() {});
    widget.onModifiersChanged?.call();
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrlChanged);
    if (widget.controller == null) {
      _ctrl.dispose();
    }
    super.dispose();
  }

  List<List<_Key>> get _rows {
    switch (_ctrl.value.mode) {
      case KeyboardMode.text:
        return _textRows;
      case KeyboardMode.numbers:
        return _numRows;
      case KeyboardMode.special:
        return _specialRows;
      case KeyboardMode.fn:
        return _fnRows;
    }
  }

  void _emit(String value) {
    widget.onKey(value, Set<String>.from(_ctrl.value.activeModifiers));
  }

  void _handleKey(_Key key) {
    final v = key.value ?? key.label;
    switch (v) {
      case '__mode_text__':
        _ctrl.toggleMode(KeyboardMode.text);
        return;
      case '__mode_numbers__':
        _ctrl.toggleMode(KeyboardMode.numbers);
        return;
      case '__mode_special__':
        _ctrl.toggleMode(KeyboardMode.special);
        return;
      case '__mode_fn__':
        _ctrl.toggleMode(KeyboardMode.fn);
        return;
      case '__shift__':
        _ctrl.toggleShift();
        return;
      case '__caps__':
        _ctrl.toggleCaps();
        return;
      case '__ctrl__':
        _ctrl.toggleModifier('ctrl');
        return;
      case '__alt__':
        _ctrl.toggleModifier('alt');
        return;
      case '__meta__':
        _ctrl.toggleModifier('meta');
        return;
      case '__back__':
        _emit('\b');
        return;
      case '__space__':
        _emit(' ');
        return;
      default:
        _emit(_ctrl.resolve(v));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _ctrl.value;
    return ColoredBox(
      color: _T.bgChrome,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeStrip(mode: state.mode, onModeChanged: _ctrl.toggleMode),
          const SizedBox(height: 4),
          if (state.activeModifiers.isNotEmpty || state.shift || state.caps)
            _ModifierBadges(state: state),
          for (final row in _rows)
            _KeyRow(keys: row, state: state, onKey: _handleKey),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ModeStrip extends StatelessWidget {
  const _ModeStrip({required this.mode, required this.onModeChanged});

  final KeyboardMode mode;
  final void Function(KeyboardMode) onModeChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _T.bgElevated,
        border: Border(bottom: BorderSide(color: _T.borderSub)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: KeyboardMode.values.map((m) {
            final active = m == mode;
            return GestureDetector(
              onTap: () => onModeChanged(m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.only(right: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: active ? _T.accentPrim : _T.bgInput,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: active ? _T.accentPrim : _T.borderDef,
                  ),
                ),
                child: Text(
                  _modeLabel(m),
                  style: GoogleFonts.ubuntuMono(
                    fontSize: 11,
                    color: active ? _T.fgStrong : _T.fgMuted,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _modeLabel(KeyboardMode m) {
    switch (m) {
      case KeyboardMode.text:
        return 'ABC';
      case KeyboardMode.numbers:
        return '123';
      case KeyboardMode.special:
        return r'$#';
      case KeyboardMode.fn:
        return 'Fn';
    }
  }
}

class _ModifierBadges extends StatelessWidget {
  const _ModifierBadges({required this.state});

  final RemoteKeyboardState state;

  @override
  Widget build(BuildContext context) {
    final badges = <String>[];
    if (state.caps) badges.add('CAPS');
    if (state.shift) badges.add('⇧');
    badges.addAll(state.activeModifiers.map((m) => m.toUpperCase()));

    return ColoredBox(
      color: _T.bgCanvas,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 4,
            children: badges
                .map(
                  (b) => DecoratedBox(
                    decoration: BoxDecoration(
                      color: _T.accentPrim.withValues(alpha: 0.18),
                      border: Border.all(color: _T.accentPrim),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      child: Text(
                        b,
                        style: GoogleFonts.ubuntuMono(
                          fontSize: 10,
                          color: _T.accentPrim,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({
    required this.keys,
    required this.state,
    required this.onKey,
  });

  final List<_Key> keys;
  final RemoteKeyboardState state;
  final void Function(_Key) onKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 3, 4, 0),
      child: Row(
        children: keys
            .map(
              (k) => Expanded(
                flex: (k.flex * 100).round(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _KeyCell(
                    keyData: k,
                    state: state,
                    onTap: () => onKey(k),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _KeyCell extends StatefulWidget {
  const _KeyCell({
    required this.keyData,
    required this.state,
    required this.onTap,
  });

  final _Key keyData;
  final RemoteKeyboardState state;
  final VoidCallback onTap;

  @override
  State<_KeyCell> createState() => _KeyCellState();
}

class _KeyCellState extends State<_KeyCell> {
  bool _pressed = false;

  bool get _isActive {
    final v = widget.keyData.value ?? widget.keyData.label;
    final s = widget.state;
    if (v == '__shift__') return s.shift;
    if (v == '__caps__') return s.caps;
    if (v == '__ctrl__') return s.activeModifiers.contains('ctrl');
    if (v == '__alt__') return s.activeModifiers.contains('alt');
    if (v == '__meta__') return s.activeModifiers.contains('meta');
    return false;
  }

  (Color bg, Color fg, Color border) get _colors {
    final k = widget.keyData;
    if (_pressed) return (_T.bgInputHov, _T.fgStrong, _T.borderDef);
    if (_isActive) return (_T.accentPrim, _T.fgStrong, _T.accentPrim);
    switch (k.role) {
      case _KeyRole.accent:
        return (_T.accentPrim, _T.fgStrong, _T.accentPrim);
      case _KeyRole.destructive:
        return (_T.bgInput, _T.statusErr, _T.statusErr.withValues(alpha: 0.5));
      case _KeyRole.action:
        return (_T.bgCanvas, _T.fgMuted, _T.borderSub);
      case _KeyRole.wide:
        return (_T.bgCanvas, _T.fgDefault, _T.borderSub);
      default:
        return (_T.bgInput, _T.fgDefault, _T.borderDef);
    }
  }

  String get _displayLabel {
    final k = widget.keyData;
    final s = widget.state;
    if (k.role == _KeyRole.wide) return 'space';
    if (k.role == _KeyRole.normal && k.label.length == 1) {
      if (s.shift || s.caps) return k.label.toUpperCase();
    }
    return k.label;
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = _colors;
    final k = widget.keyData;
    final isFn = widget.state.mode == KeyboardMode.fn;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        height: isFn ? 36 : 42,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: border, width: 0.8),
          boxShadow: _pressed
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    offset: const Offset(0, 1.5),
                    blurRadius: 1,
                  ),
                ],
        ),
        child: Stack(
          children: [
            if (k.sublabel != null)
              Positioned(
                top: 3,
                left: 4,
                child: Text(
                  k.sublabel!,
                  style: GoogleFonts.ubuntuMono(
                    fontSize: 8,
                    color: _T.fgInactive,
                  ),
                ),
              ),
            Center(
              child: Text(
                _displayLabel,
                style: k.role == _KeyRole.normal
                    ? GoogleFonts.ubuntu(
                        fontSize: isFn ? 11 : 14,
                        color: fg,
                        fontWeight: FontWeight.w500,
                      )
                    : GoogleFonts.ubuntuMono(
                        fontSize: isFn ? 10 : 12,
                        color: fg,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
