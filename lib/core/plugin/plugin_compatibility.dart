import 'plugin_manifest.dart';

/// Version gate shared by package inspection and runtime startup.
class PluginCompatibility {
  PluginCompatibility._();

  /// ABI implemented by this host.
  static const String apiVersion = '1.0';

  /// Reported host version. Kept at the QPlayer line this app is compatible
  /// with, so official plugins authored for QPlayer 1.9.x accept this host.
  static const String hostVersion = '1.9.7';

  static void requireCompatible(PluginManifest manifest) {
    final requestedApi = _numbers(manifest.apiVersion);
    final supportedApi = _numbers(apiVersion);
    if (requestedApi[0] != supportedApi[0] ||
        requestedApi[1] > supportedApi[1]) {
      throw ArgumentError('unsupported plugin API ${manifest.apiVersion}');
    }
    if (manifest.minHostVersion.isNotEmpty &&
        compare(manifest.minHostVersion, hostVersion) > 0) {
      throw ArgumentError(
          'plugin requires QPlayer ${manifest.minHostVersion} or later');
    }
  }

  static void requireHostAtLeast(String minimum) {
    if (minimum.isNotEmpty && compare(minimum, hostVersion) > 0) {
      throw ArgumentError('plugin requires QPlayer $minimum or later');
    }
  }

  static int compare(String left, String right) {
    final a = _numbers(left);
    final b = _numbers(right);
    for (var i = 0; i < 4; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return 0;
  }

  static List<int> _numbers(String value) {
    final out = List<int>.filled(4, 0);
    final core = value.split(RegExp(r'[-+]')).first;
    final parts = core.split('.');
    for (var i = 0; i < 4 && i < parts.length; i++) {
      out[i] = int.tryParse(parts[i]) ?? 0;
    }
    return out;
  }
}
