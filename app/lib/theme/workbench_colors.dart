import 'package:flutter/material.dart';

@immutable
class WorkbenchColors extends ThemeExtension<WorkbenchColors> {
  const WorkbenchColors({
    required this.app,
    required this.chrome,
    required this.canvas,
    required this.elevated,
    required this.input,
    required this.inputHover,
    required this.borderSubtle,
    required this.borderDefault,
    required this.fgDefault,
    required this.fgStrong,
    required this.fgMuted,
    required this.fgInactive,
    required this.fgPlaceholder,
    required this.accentPrimary,
    required this.accentPrimaryHover,
    required this.statusError,
    required this.statusSuccess,
    required this.aiCommandBg,
    required this.aiCommandFg,
    required this.aiEditedFileFg,
  });

  final Color app;
  final Color chrome;
  final Color canvas;
  final Color elevated;
  final Color input;
  final Color inputHover;
  final Color borderSubtle;
  final Color borderDefault;
  final Color fgDefault;
  final Color fgStrong;
  final Color fgMuted;
  final Color fgInactive;
  final Color fgPlaceholder;
  final Color accentPrimary;
  final Color accentPrimaryHover;
  final Color statusError;
  final Color statusSuccess;
  final Color aiCommandBg;
  final Color aiCommandFg;
  final Color aiEditedFileFg;

  @override
  WorkbenchColors copyWith({
    Color? app,
    Color? chrome,
    Color? canvas,
    Color? elevated,
    Color? input,
    Color? inputHover,
    Color? borderSubtle,
    Color? borderDefault,
    Color? fgDefault,
    Color? fgStrong,
    Color? fgMuted,
    Color? fgInactive,
    Color? fgPlaceholder,
    Color? accentPrimary,
    Color? accentPrimaryHover,
    Color? statusError,
    Color? statusSuccess,
    Color? aiCommandBg,
    Color? aiCommandFg,
    Color? aiEditedFileFg,
  }) {
    return WorkbenchColors(
      app: app ?? this.app,
      chrome: chrome ?? this.chrome,
      canvas: canvas ?? this.canvas,
      elevated: elevated ?? this.elevated,
      input: input ?? this.input,
      inputHover: inputHover ?? this.inputHover,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderDefault: borderDefault ?? this.borderDefault,
      fgDefault: fgDefault ?? this.fgDefault,
      fgStrong: fgStrong ?? this.fgStrong,
      fgMuted: fgMuted ?? this.fgMuted,
      fgInactive: fgInactive ?? this.fgInactive,
      fgPlaceholder: fgPlaceholder ?? this.fgPlaceholder,
      accentPrimary: accentPrimary ?? this.accentPrimary,
      accentPrimaryHover: accentPrimaryHover ?? this.accentPrimaryHover,
      statusError: statusError ?? this.statusError,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      aiCommandBg: aiCommandBg ?? this.aiCommandBg,
      aiCommandFg: aiCommandFg ?? this.aiCommandFg,
      aiEditedFileFg: aiEditedFileFg ?? this.aiEditedFileFg,
    );
  }

  @override
  WorkbenchColors lerp(ThemeExtension<WorkbenchColors>? other, double t) {
    if (other is! WorkbenchColors) {
      return this;
    }
    return this;
  }
}

extension WorkbenchThemeX on BuildContext {
  WorkbenchColors get workbenchColors {
    return Theme.of(this).extension<WorkbenchColors>()!;
  }
}
