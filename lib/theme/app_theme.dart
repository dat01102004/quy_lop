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
    // không cần lerp phức tạp cho gradient
    return t < 0.5 ? this : other;
  }

  // === MÀU NỀN LIGHT (đổi ở đây)
  static AppGradients light() => const AppGradients(
    background: LinearGradient(
      colors: [Color(0xFFF2F5FF), Color(0xFFFFFFFF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  // === MÀU NỀN DARK (đổi ở đây)
  static AppGradients dark() => const AppGradients(
    background: LinearGradient(
      colors: [Color(0xFF2F1156), Color(0xFF0F172A)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
  );
}
