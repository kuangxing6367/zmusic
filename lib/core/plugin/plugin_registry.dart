import 'dart:convert';
import 'dart:io';

import 'installed_plugin.dart';

/// Persisted list of installed plugins (enable/disable, primary source,
/// approved permissions and package digests).
class PluginRegistry {
  PluginRegistry(this.file);

  final File file;
  final List<InstalledPlugin> _plugins = [];

  List<InstalledPlugin> get plugins => List.unmodifiable(_plugins);

  InstalledPlugin? get(String id) {
    for (final plugin in _plugins) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }

  InstalledPlugin? get primary {
    for (final plugin in _plugins) {
      if (plugin.primary && plugin.enabled) return plugin;
    }
    return null;
  }

  List<InstalledPlugin> get enabled =>
      _plugins.where((plugin) => plugin.enabled).toList();

  Future<void> load() async {
    _plugins.clear();
    if (!await file.exists()) return;
    try {
      final raw = jsonDecode(await file.readAsString());
      final list = (raw is Map ? raw['plugins'] : raw) as List?;
      if (list != null) {
        for (final item in list) {
          if (item is Map) {
            _plugins.add(
                InstalledPlugin.fromJson(item.cast<String, dynamic>()));
          }
        }
      }
    } catch (_) {
      // A corrupt registry is treated as empty; packages remain on disk and
      // can be re-imported without losing credentials.
    }
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode({
      'schemaVersion': 1,
      'plugins': _plugins.map((p) => p.toJson()).toList(),
    }), flush: true);
    await temp.rename(file.path);
  }

  Future<void> upsert(InstalledPlugin plugin) async {
    final index = _plugins.indexWhere((p) => p.id == plugin.id);
    if (index >= 0) {
      _plugins[index] = plugin;
    } else {
      _plugins.add(plugin);
    }
    await save();
  }

  Future<void> remove(String id) async {
    _plugins.removeWhere((plugin) => plugin.id == id);
    await save();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final index = _plugins.indexWhere((p) => p.id == id);
    if (index < 0) return;
    var updated = _plugins[index].copyWith(enabled: enabled);
    if (!enabled) updated = updated.copyWith(primary: false);
    _plugins[index] = updated;
    await save();
  }

  Future<void> setPrimary(String id) async {
    for (var i = 0; i < _plugins.length; i++) {
      _plugins[i] = _plugins[i].copyWith(primary: _plugins[i].id == id);
    }
    await save();
  }
}
