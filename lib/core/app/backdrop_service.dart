import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'appearance_settings.dart';

/// Resolves the shell backdrop to an image URL.
///
/// Two public, key-less services are supported:
/// * Bing's daily wallpaper (`HPImageArchive`), picking a random day from the
///   last week so the backdrop changes between launches;
/// * `api.furry.ist`, a random landscape illustration (JSON endpoint).
///
/// Results are cached per source for the lifetime of the app; the settings page
/// bumps [AppearanceSettings.backdropRevision] to force a new pick.
class BackdropService {
  BackdropService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 10),
              ),
            );

  final Dio _dio;
  final math.Random _random = math.Random();

  final Map<String, String> _cache = {};

  Future<String> resolve(
    BackdropSource source, {
    String customUrl = '',
    int revision = 0,
    double displayWidth = 0,
  }) async {
    switch (source) {
      case BackdropSource.none:
      case BackdropSource.cover:
        return '';
      case BackdropSource.custom:
        return customUrl.trim();
      case BackdropSource.bing:
        return _cached('bing:$revision', () => _bing(displayWidth));
      case BackdropSource.furry:
        return _cached('furry:$revision', _furry);
    }
  }

  Future<String> _cached(String key, Future<String> Function() load) async {
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final url = await load();
      if (url.isNotEmpty) {
        // Keep at most a couple of entries; the revision makes old keys dead.
        if (_cache.length > 4) _cache.clear();
        _cache[key] = url;
      }
      return url;
    } catch (e) {
      debugPrint('[backdrop] $key failed: $e');
      return '';
    }
  }

  Future<String> _bing(double displayWidth) async {
    // idx 0 is today, -1 yesterday; sample the last week like the classic
    // "random Bing wallpaper" snippets.
    final idx = _random.nextInt(9) - 1;
    final response = await _dio.get<dynamic>(
      'https://www.bing.com/HPImageArchive.aspx',
      queryParameters: {
        'format': 'js',
        'idx': idx,
        'n': 1,
        'mkt': 'zh-CN',
      },
    );
    final data = response.data;
    if (data is! Map) return '';
    final images = data['images'];
    if (images is! List || images.isEmpty) return '';
    final first = images.first;
    if (first is! Map) return '';
    final base = first['urlbase']?.toString() ?? '';
    if (base.isEmpty) return '';
    // 1080p is upscaled to mush on a 2K/4K monitor; Bing serves a UHD variant.
    final suffix = displayWidth >= 2560 ? '_UHD.jpg' : '_1920x1080.jpg';
    return 'https://www.bing.com$base$suffix';
  }

  Future<String> _furry() async {
    final response = await _dio.get<dynamic>(
      'https://api.furry.ist/furry-img/',
      queryParameters: {'format': 'json', 'mode': 'large'},
    );
    final data = response.data;
    if (data is Map) {
      final url = data['url']?.toString() ?? '';
      if (url.isNotEmpty) return url;
    }
    // Fall back to the redirect endpoint when the JSON shape changes.
    return 'https://api.furry.ist/furry-img/?mode=large';
  }
}
