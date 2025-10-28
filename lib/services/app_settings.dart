import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final ThemeMode mode;
  final int seed;
  final String locale;
  final double textScale;
  const AppSettings({required this.mode, required this.seed, required this.locale, required this.textScale});

  AppSettings copyWith({ThemeMode? mode, int? seed, String? locale, double? textScale}) => AppSettings(
    mode: mode ?? this.mode,
    seed: seed ?? this.seed,
    locale: locale ?? this.locale,
    textScale: textScale ?? this.textScale,
  );

  static const _k = ('mode','seed','locale','textScale');

  static Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    final modeIdx = p.getInt(_k.$1) ?? 0;
    return AppSettings(
      mode: ThemeMode.values[modeIdx],
      seed: p.getInt(_k.$2) ?? const Color(0xFF6D4BF1).value,
      locale: p.getString(_k.$3) ?? 'vi',
      textScale: p.getDouble(_k.$4) ?? 1.0,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_k.$1, mode.index);
    await p.setInt(_k.$2, seed);
    await p.setString(_k.$3, locale);
    await p.setDouble(_k.$4, textScale);
  }
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    // Trạng thái mặc định ngay lập tức
    final def = const AppSettings(
      mode: ThemeMode.system, seed: 0xFF6D4BF1, locale: 'vi', textScale: 1.0,
    );
    // Nạp async từ SharedPreferences rồi cập nhật
    _loadAsync();
    return def;
  }

  Future<void> _loadAsync() async {
    final loaded = await AppSettings.load();
    state = loaded;
  }

  Future<void> setMode(ThemeMode m) async { state = state.copyWith(mode: m); await state.save(); }
  Future<void> setSeed(Color c) async     { state = state.copyWith(seed: c.value); await state.save(); }
  Future<void> setLocale(String l) async  { state = state.copyWith(locale: l); await state.save(); }
  Future<void> setTextScale(double s) async {
    state = state.copyWith(textScale: s.clamp(.8, 1.6));
    await state.save();
  }
}

// Provider kiểu Notifier
final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
