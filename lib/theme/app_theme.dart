// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

@immutable
class AppGradients extends ThemeExtension<AppGradients> {
  final Gradient background;
  const AppGradients({required this.background});

  @override
  AppGradients copyWith({Gradient? background}) =>
      AppGradients(background: background ?? this.background);

  @override
  AppGradients lerp(ThemeExtension<AppGradients>? other, double t) {
    if (other is! AppGradients) return this;
    return AppGradients(
        background: LinearGradient.lerp(
            background as LinearGradient, other.background as LinearGradient, t)!
    );
  }
}

ThemeData lightTheme(Color seed) {
  final cs = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
  return ThemeData(
    colorScheme: cs,
    useMaterial3: true,
  ).copyWith(extensions: [
    AppGradients(
      background: const LinearGradient(
        colors: [Color(0xFFF2F5FF), Color(0xFFFFFFFF)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
    ),
  ]);
}

ThemeData darkTheme(Color seed) {
  final cs = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
  return ThemeData(
    colorScheme: cs,
    useMaterial3: true,
  ).copyWith(extensions: [
    AppGradients(
      background: const LinearGradient(
        colors: [Color(0xFF2F1156), Color(0xFF0F172A)],
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
      ),
    ),
  ]);
}
