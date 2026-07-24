import 'package:flutter/material.dart';

/// Light/dark themes for the app shell. Editor-specific fonts (writing/export)
/// are a separate concern, scoped for Phase 1 — see PLAN.md "Manuscript
/// Structure & Formatting".
class AppTheme {
  AppTheme._();

  static const _seed = Color(0xFF4A3B78); // matches the -aity family's purple identity

  static ThemeData light() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light),
        brightness: Brightness.light,
      );

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
        brightness: Brightness.dark,
      );
}
