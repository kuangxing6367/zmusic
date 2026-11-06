import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted lyric appearance preferences shared by the player page and the
/// desktop lyric window.
class LyricSettings extends ChangeNotifier {
  static const _kFontSize = 'lyric.fontSize';
  static const _kFontWeight = 'lyric.fontWeight';
  static const _kLineSpacing = 'lyric.lineSpacing';
  static const _kAlignment = 'lyric.alignment';
  static const _kTranslation = 'lyric.translation';
  static const _kRomanization = 'lyric.romanization';
  static const _kShadow = 'lyric.shadow';
  static const _kFontFamily = 'lyric.fontFamily';
  static const _kDesktopFontSize = 'desktopLyric.fontSize';
  static const _kDesktopBackground = 'desktopLyric.background';
  static const _kIsland = 'lyric.island';
  static const _kIslandCapsule = 'lyric.islandCapsule';
  static const _kIslandLyrics = 'lyric.islandLyrics';
  static const _kIslandFallback = 'lyric.islandFallback';

  SharedPreferences? _prefs;

  double fontSize = 24;
  int fontWeightValue = 500;
  double lineSpacing = 1.6;
  String alignment = 'duet';
  bool showTranslation = true;
  bool showRomanization = true;
  bool shadow = true;
  String fontFamily = '';
  double desktopFontSize = 34;
  double desktopBackgroundOpacity = 0.62;

  /// Publishes lyrics to the Android system lyric provider (Lyricon / 词幕).
  /// On systems without that module nothing is drawn by the app.
  bool showIsland = true;

  /// Draws the app's own lyric capsule below the status bar. Disabled by
  /// default because the native island / provider looks better on modern
  /// Android builds.
  bool showIslandCapsule = false;

  /// When the in-app capsule is enabled, show the current lyric line instead
  /// of the song title (default keeps the song title).
  bool islandLyrics = false;

  /// Android 16+ only: fall back to a promoted live-update notification when
  /// no system lyric provider is installed.
  bool islandFallbackNotification = false;

  FontWeight get fontWeight => switch (fontWeightValue) {
        300 => FontWeight.w300,
        400 => FontWeight.w400,
        500 => FontWeight.w500,
        _ => FontWeight.w600,
      };

  Future<void> load(SharedPreferences prefs) async {
    _prefs = prefs;
    fontSize = (prefs.getDouble(_kFontSize) ?? fontSize).clamp(14, 40).toDouble();
    fontWeightValue = (prefs.getInt(_kFontWeight) ?? fontWeightValue)
        .clamp(300, 600);
    lineSpacing = (prefs.getDouble(_kLineSpacing) ?? lineSpacing).clamp(1.1, 2.4).toDouble();
    alignment = prefs.getString(_kAlignment) ?? alignment;
    showTranslation = prefs.getBool(_kTranslation) ?? showTranslation;
    showRomanization = prefs.getBool(_kRomanization) ?? showRomanization;
    shadow = prefs.getBool(_kShadow) ?? shadow;
    fontFamily = prefs.getString(_kFontFamily) ?? fontFamily;
    desktopFontSize = (prefs.getDouble(_kDesktopFontSize) ?? desktopFontSize).clamp(18, 38).toDouble();
    desktopBackgroundOpacity =
        (prefs.getDouble(_kDesktopBackground) ?? desktopBackgroundOpacity).clamp(0.0, 0.9).toDouble();
    showIsland = prefs.getBool(_kIsland) ?? showIsland;
    showIslandCapsule = prefs.getBool(_kIslandCapsule) ?? showIslandCapsule;
    islandLyrics = prefs.getBool(_kIslandLyrics) ?? islandLyrics;
    islandFallbackNotification =
        prefs.getBool(_kIslandFallback) ?? islandFallbackNotification;
    notifyListeners();
  }

  void setFontSize(double value) {
    final next = value.clamp(14, 40).toDouble();
    if (next == fontSize) return;
    fontSize = next;
    notifyListeners();
    unawaited(_prefs?.setDouble(_kFontSize, next));
  }

  void setFontWeight(int value) {
    final next = value.clamp(300, 600);
    if (next == fontWeightValue) return;
    fontWeightValue = next;
    notifyListeners();
    unawaited(_prefs?.setInt(_kFontWeight, next));
  }

  void setLineSpacing(double value) {
    final next = value.clamp(1.1, 2.4).toDouble();
    if (next == lineSpacing) return;
    lineSpacing = next;
    notifyListeners();
    unawaited(_prefs?.setDouble(_kLineSpacing, next));
  }

  void setAlignment(String value) {
    if (!const {'duet', 'left', 'center', 'right'}.contains(value)) return;
    if (value == alignment) return;
    alignment = value;
    notifyListeners();
    unawaited(_prefs?.setString(_kAlignment, value));
  }

  void setShowTranslation(bool value) {
    if (value == showTranslation) return;
    showTranslation = value;
    notifyListeners();
    unawaited(_prefs?.setBool(_kTranslation, value));
  }

  void setShowRomanization(bool value) {
    if (value == showRomanization) return;
    showRomanization = value;
    notifyListeners();
    unawaited(_prefs?.setBool(_kRomanization, value));
  }

  void setShadow(bool value) {
    if (value == shadow) return;
    shadow = value;
    notifyListeners();
    unawaited(_prefs?.setBool(_kShadow, value));
  }

  void setFontFamily(String value) {
    if (value == fontFamily) return;
    fontFamily = value;
    notifyListeners();
    unawaited(_prefs?.setString(_kFontFamily, value));
  }

  void setDesktopFontSize(double value) {
    final next = value.clamp(18, 38).toDouble();
    if (next == desktopFontSize) return;
    desktopFontSize = next;
    notifyListeners();
    unawaited(_prefs?.setDouble(_kDesktopFontSize, next));
  }

  void setDesktopBackgroundOpacity(double value) {
    final next = value.clamp(0.0, 0.9).toDouble();
    if (next == desktopBackgroundOpacity) return;
    desktopBackgroundOpacity = next;
    notifyListeners();
    unawaited(_prefs?.setDouble(_kDesktopBackground, next));
  }

  void setShowIsland(bool value) {
    if (value == showIsland) return;
    showIsland = value;
    notifyListeners();
    unawaited(_prefs?.setBool(_kIsland, value));
  }

  void setShowIslandCapsule(bool value) {
    if (value == showIslandCapsule) return;
    showIslandCapsule = value;
    notifyListeners();
    unawaited(_prefs?.setBool(_kIslandCapsule, value));
  }

  void setIslandLyrics(bool value) {
    if (value == islandLyrics) return;
    islandLyrics = value;
    notifyListeners();
    unawaited(_prefs?.setBool(_kIslandLyrics, value));
  }

  void setIslandFallbackNotification(bool value) {
    if (value == islandFallbackNotification) return;
    islandFallbackNotification = value;
    notifyListeners();
    unawaited(_prefs?.setBool(_kIslandFallback, value));
  }
}

