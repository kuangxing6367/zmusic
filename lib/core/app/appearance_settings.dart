import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the shell backdrop image comes from.
enum BackdropSource {
  /// No image; the plain theme surface is used.
  none,

  /// Blurred artwork of the song that is currently playing.
  cover,

  /// Bing's daily wallpaper (random day from the last week).
  bing,

  /// Random landscape illustration from api.furry.ist.
  furry,

  /// User supplied image URL.
  custom;

  static BackdropSource parse(String raw) => values.firstWhere(
        (value) => value.name == raw,
        orElse: () => BackdropSource.none,
      );
}

/// Persisted appearance preferences: accent colour and the page backdrop.
///
/// Kept separate from [AppController] so the settings page can rebuild on
/// appearance changes without waiting for the whole controller graph.
class AppearanceSettings extends ChangeNotifier {
  static const _kSeed = 'ui.seedColor';
  static const _kBackdropSource = 'ui.backdropSource';
  static const _kBackdropUrl = 'ui.backdropUrl';
  static const _kBackdropOpacity = 'ui.backdropOpacity';
  static const _kBackdropBlur = 'ui.backdropBlur';

  /// A small, tasteful palette instead of a full colour wheel: picking a hue is
  /// one tap, and every entry keeps the Material 3 tonal scheme readable.
  static const List<Color> seedPresets = [
    Color(0xFF4C6FFF),
    Color(0xFF7C5CFF),
    Color(0xFFB45CE0),
    Color(0xFFE85C8A),
    Color(0xFFE5484D),
    Color(0xFFFF7A3D),
    Color(0xFFF5A524),
    Color(0xFF2FBF71),
    Color(0xFF00B4C8),
    Color(0xFF6B7280),
  ];

  static const double defaultOpacity = 0.42;
  static const double defaultBlur = 26;

  SharedPreferences? _prefs;

  Color seedColor = const Color(0xFF4C6FFF);
  BackdropSource backdropSource = BackdropSource.none;
  String backdropUrl = '';
  double backdropOpacity = defaultOpacity;
  double backdropBlur = defaultBlur;

  /// Bumped whenever the user asks for another random image.
  int backdropRevision = 0;

  Future<void> load(SharedPreferences prefs) async {
    _prefs = prefs;
    final seed = prefs.getInt(_kSeed);
    if (seed != null) seedColor = Color(seed);
    backdropSource = BackdropSource.parse(
      prefs.getString(_kBackdropSource) ?? '',
    );
    backdropUrl = prefs.getString(_kBackdropUrl) ?? '';
    backdropOpacity = (prefs.getDouble(_kBackdropOpacity) ?? backdropOpacity)
        .clamp(0.0, 0.9)
        .toDouble();
    backdropBlur =
        (prefs.getDouble(_kBackdropBlur) ?? backdropBlur).clamp(0.0, 60.0).toDouble();
    notifyListeners();
  }

  void setSeedColor(Color value) {
    if (value.toARGB32() == seedColor.toARGB32()) return;
    seedColor = value;
    notifyListeners();
    unawaited(_prefs?.setInt(_kSeed, value.toARGB32()));
  }

  void setBackdropSource(BackdropSource value) {
    if (value == backdropSource) return;
    backdropSource = value;
    backdropRevision++;
    notifyListeners();
    unawaited(_prefs?.setString(_kBackdropSource, value.name));
  }

  void setBackdropUrl(String value) {
    final next = value.trim();
    if (next == backdropUrl) return;
    backdropUrl = next;
    backdropRevision++;
    notifyListeners();
    unawaited(_prefs?.setString(_kBackdropUrl, next));
  }

  void setBackdropOpacity(double value) {
    final next = value.clamp(0.0, 0.9).toDouble();
    if (next == backdropOpacity) return;
    backdropOpacity = next;
    notifyListeners();
    unawaited(_prefs?.setDouble(_kBackdropOpacity, next));
  }

  void setBackdropBlur(double value) {
    final next = value.clamp(0.0, 60.0).toDouble();
    if (next == backdropBlur) return;
    backdropBlur = next;
    notifyListeners();
    unawaited(_prefs?.setDouble(_kBackdropBlur, next));
  }

  /// Next Bing day / another random illustration.
  void shuffleBackdrop() {
    backdropRevision++;
    notifyListeners();
  }
}
