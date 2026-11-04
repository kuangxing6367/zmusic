import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.repo,
    required this.publisherKey,
  });

  final String id;
  final String name;
  final String description;
  final String repo;
  final String publisherKey;

  static CatalogEntry fromJson(Map<String, dynamic> json) => CatalogEntry(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        repo: json['repo']?.toString() ?? '',
        publisherKey: json['publisherKey']?.toString() ?? '',
      );
}

class CatalogRelease {
  CatalogRelease({
    required this.entry,
    this.tag = '',
    this.downloadUrl = '',
    this.notes = '',
    this.error = '',
    this.installedVersion = '',
    this.updateAvailable = false,
  });

  final CatalogEntry entry;
  final String tag;
  final String downloadUrl;
  final String notes;
  final String error;
  final String installedVersion;
  final bool updateAvailable;

  String get displayVersion => tag.replaceFirst(RegExp(r'^v'), '');
}

/// Reads the bundled, host-pinned plugin catalog and queries GitHub's latest
/// release endpoint for each repository.
class PluginCatalogService {
  PluginCatalogService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  List<CatalogEntry>? _entries;

  Future<List<CatalogEntry>> entries() async {
    final cached = _entries;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/plugin-catalog.json');
    final list = (jsonDecode(raw) as List)
        .whereType<Map>()
        .map((item) => CatalogEntry.fromJson(item.cast<String, dynamic>()))
        .toList();
    _entries = list;
    return list;
  }

  Future<List<CatalogRelease>> releases({
    Map<String, String> installedVersions = const {},
  }) async {
    final list = await entries();
    final results = await Future.wait(
      list.map((entry) async {
        try {
          final release = await _latestRelease(entry);
          final installed = installedVersions[entry.id] ?? '';
          return CatalogRelease(
            entry: entry,
            tag: release.$1,
            downloadUrl: release.$2,
            notes: release.$3,
            installedVersion: installed,
            updateAvailable: installed.isNotEmpty &&
                _versionGreater(release.$1.replaceFirst(RegExp(r'^v'), ''), installed),
          );
        } catch (e) {
          return CatalogRelease(
            entry: entry,
            error: e.toString(),
            installedVersion: installedVersions[entry.id] ?? '',
          );
        }
      }),
    );
    return results;
  }

  Future<(String, String, String)> _latestRelease(CatalogEntry entry) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://api.github.com/repos/${entry.repo}/releases/latest',
      options: Options(
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'QPlayer-Flutter',
        },
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    if (response.statusCode != 200) {
      throw Exception('GitHub API ${response.statusCode}');
    }
    final data = response.data ?? const <String, dynamic>{};
    final tag = data['tag_name']?.toString() ?? '';
    final assets = data['assets'];
    var downloadUrl = '';
    if (assets is List) {
      for (final asset in assets) {
        if (asset is Map &&
            (asset['name']?.toString().toLowerCase().endsWith('.qplug') ??
                false)) {
          downloadUrl = asset['browser_download_url']?.toString() ?? '';
          break;
        }
      }
    }
    if (downloadUrl.isEmpty) throw Exception('该版本没有 .qplug 资产');
    return (tag, downloadUrl, data['body']?.toString() ?? '');
  }

  static bool _versionGreater(String a, String b) {
    List<int> numbers(String value) {
      final out = List<int>.filled(4, 0);
      final parts = value.split(RegExp(r'[-+]')).first.split('.');
      for (var i = 0; i < 4 && i < parts.length; i++) {
        out[i] = int.tryParse(parts[i]) ?? 0;
      }
      return out;
    }

    final left = numbers(a);
    final right = numbers(b);
    for (var i = 0; i < 4; i++) {
      if (left[i] != right[i]) return left[i] > right[i];
    }
    return false;
  }
}
