import 'plugin_manifest.dart';
import 'plugin_permission.dart';

class InstalledPlugin {
  InstalledPlugin({
    required this.manifest,
    required this.directory,
    this.enabled = true,
    this.primary = false,
    this.signed = false,
    this.packageDigest = '',
    this.permissions = const [],
    this.installedAtMs = 0,
  });

  final PluginManifest manifest;
  final String directory;
  final bool enabled;
  final bool primary;
  final bool signed;
  final String packageDigest;
  final List<String> permissions;
  final int installedAtMs;

  String get id => manifest.id;
  String get name => manifest.name;
  String get version => manifest.version;

  InstalledPlugin copyWith({
    PluginManifest? manifest,
    String? directory,
    bool? enabled,
    bool? primary,
    bool? signed,
    String? packageDigest,
    List<String>? permissions,
    int? installedAtMs,
  }) {
    return InstalledPlugin(
      manifest: manifest ?? this.manifest,
      directory: directory ?? this.directory,
      enabled: enabled ?? this.enabled,
      primary: primary ?? this.primary,
      signed: signed ?? this.signed,
      packageDigest: packageDigest ?? this.packageDigest,
      permissions: permissions ?? this.permissions,
      installedAtMs: installedAtMs ?? this.installedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'manifest': manifest.toJson(),
        'directory': directory,
        'enabled': enabled,
        'primary': primary,
        'signed': signed,
        'packageDigest': packageDigest,
        'permissions': permissions,
        'installedAtMs': installedAtMs,
      };

  static InstalledPlugin fromJson(Map<String, dynamic> json) {
    final rawManifest = json['manifest'];
    return InstalledPlugin(
      manifest: rawManifest is Map
          ? PluginManifest.fromJson(rawManifest.cast<String, dynamic>())
          : PluginManifest(),
      directory: json['directory']?.toString() ?? '',
      enabled: json['enabled'] as bool? ?? true,
      primary: json['primary'] as bool? ?? false,
      signed: json['signed'] as bool? ?? false,
      packageDigest: json['packageDigest']?.toString() ?? '',
      permissions: (json['permissions'] as List?)
              ?.map((v) => v.toString())
              .toList() ??
          const [],
      installedAtMs: (json['installedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  Set<PluginPermission> get permissionSet =>
      permissions.map(PluginPermission.fromWireName).toSet();
}
