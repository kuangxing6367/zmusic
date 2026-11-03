import '../media/media_id.dart';
import 'plugin_permission.dart';
import 'provider_capability.dart';

class UiContribution {
  const UiContribution({
    required this.id,
    required this.placement,
    this.source = '',
    this.label = '',
    this.icon = 'extension',
  });

  final String id;
  final String placement;
  final String source;
  final String label;
  final String icon;

  Map<String, dynamic> toJson() => {
        'id': id,
        'placement': placement,
        if (source.isNotEmpty) 'source': source,
        'label': label,
        'icon': icon,
      };

  static UiContribution fromJson(Map<String, dynamic> json) => UiContribution(
        id: json['id']?.toString() ?? '',
        placement: json['placement']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        icon: json['icon']?.toString() ?? 'extension',
      );
}

/// Parsed `plugin.json`; all fields are data-only.
class PluginManifest {
  PluginManifest({
    this.schemaVersion = 1,
    this.id = '',
    this.name = '',
    this.version = '',
    this.apiVersion = '',
    this.minHostVersion = '',
    this.entry = 'main.js',
    this.publisher = '',
    this.icon = '',
    this.capabilities = const [],
    this.permissions = const [],
    this.networkDomains = const [],
    this.networkMethods = const [],
    this.ui = const [],
  });

  static const int currentSchema = 1;
  static const int maxUiContributions = 8;

  static final RegExp _versionPattern =
      RegExp(r'^[0-9]+(?:\.[0-9]+){0,3}(?:[-+][A-Za-z0-9._-]+)?$');
  static final RegExp _domainPattern = RegExp(
      r'^(?:\*\.)?[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$');
  static final RegExp _uiIdPattern = RegExp(r'^[a-z][a-z0-9._-]{0,63}$');
  static final RegExp _uiIconPattern = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

  final int schemaVersion;
  final String id;
  final String name;
  final String version;
  final String apiVersion;
  final String minHostVersion;
  final String entry;
  final String publisher;
  final String icon;
  final List<String> capabilities;
  final List<String> permissions;
  final List<String> networkDomains;
  final List<String> networkMethods;
  final List<UiContribution> ui;

  Set<ProviderCapability> get capabilitySet =>
      capabilities.map(ProviderCapability.fromWireName).toSet();

  Set<PluginPermission> get permissionSet =>
      permissions.map(PluginPermission.fromWireName).toSet();

  bool hasCapability(ProviderCapability capability) =>
      capabilities.contains(capability.wireName);

  bool hasPermission(PluginPermission permission) =>
      permissions.contains(permission.wireName);

  static PluginManifest fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) => (json[key] as List?)
            ?.map((v) => v?.toString() ?? '')
            .toList() ??
        const [];
    final ui = <UiContribution>[];
    final rawUi = json['ui'];
    if (rawUi is List) {
      for (final item in rawUi) {
        if (item is Map) {
          ui.add(UiContribution.fromJson(item.cast<String, dynamic>()));
        }
      }
    }
    return PluginManifest(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 0,
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      apiVersion: json['apiVersion']?.toString() ?? '',
      minHostVersion: json['minHostVersion']?.toString() ?? '',
      entry: json['entry']?.toString() ?? 'main.js',
      publisher: json['publisher']?.toString() ?? '',
      icon: json['icon']?.toString() ?? '',
      capabilities: strings('capabilities'),
      permissions: strings('permissions'),
      networkDomains: strings('networkDomains'),
      networkMethods: strings('networkMethods'),
      ui: ui,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'version': version,
        'apiVersion': apiVersion,
        'minHostVersion': minHostVersion,
        'entry': entry,
        'publisher': publisher,
        'icon': icon,
        'capabilities': capabilities,
        'permissions': permissions,
        'networkDomains': networkDomains,
        'networkMethods': networkMethods,
        'ui': ui.map((c) => c.toJson()).toList(),
      };

  void validate() {
    if (schemaVersion != currentSchema) {
      throw ArgumentError('unsupported plugin schema $schemaVersion');
    }
    if (!MediaId.isValidProvider(id)) {
      throw ArgumentError('invalid plugin id: $id');
    }
    if (id == 'local') {
      throw ArgumentError("plugin id 'local' is reserved");
    }
    if (name.trim().isEmpty || name.length > 80) {
      throw ArgumentError('invalid plugin name');
    }
    _requireVersion('version', version);
    _requireVersion('apiVersion', apiVersion);
    if (minHostVersion.isNotEmpty) {
      _requireVersion('minHostVersion', minHostVersion);
    }
    requirePackagePath('entry', entry, '.js');
    if (icon.isNotEmpty) requirePackagePath('icon', icon, null);

    final capabilitySet = _unique('capability', capabilities);
    for (final capability in capabilitySet) {
      ProviderCapability.fromWireName(capability);
    }
    final permissionSet = _unique('permission', permissions);
    for (final permission in permissionSet) {
      PluginPermission.fromWireName(permission);
    }
    if (capabilitySet.contains(ProviderCapability.login.wireName) &&
        !permissionSet.contains(PluginPermission.credentials.wireName)) {
      throw ArgumentError('login capability requires credentials permission');
    }
    if (networkDomains.isNotEmpty &&
        !permissionSet.contains(PluginPermission.network.wireName)) {
      throw ArgumentError('networkDomains requires network permission');
    }
    final domains = <String>{};
    for (final raw in networkDomains) {
      final domain = raw.toLowerCase();
      if (!_domainPattern.hasMatch(domain)) {
        throw ArgumentError('invalid network domain: $raw');
      }
      if (!domains.add(domain)) {
        throw ArgumentError('duplicate network domain: $raw');
      }
    }
    final methods = _unique('network method', networkMethods);
    for (final method in methods) {
      if (!RegExp(r'^(GET|POST|PUT|PATCH|DELETE|HEAD)$').hasMatch(method)) {
        throw ArgumentError('invalid network method: $method');
      }
    }
    if (ui.length > maxUiContributions) {
      throw ArgumentError('too many UI contributions');
    }
    final contributionIds = <String>{};
    for (final contribution in ui) {
      if (!_uiIdPattern.hasMatch(contribution.id)) {
        throw ArgumentError('invalid UI contribution id');
      }
      if (!contributionIds.add(contribution.id)) {
        throw ArgumentError('duplicate UI contribution ${contribution.id}');
      }
      if (!RegExp(r'^[a-z][a-zA-Z0-9._-]{0,63}$')
          .hasMatch(contribution.placement)) {
        throw ArgumentError('invalid UI placement');
      }
      if (contribution.label.length > 40) {
        throw ArgumentError('invalid UI contribution label');
      }
      if (!_uiIconPattern.hasMatch(contribution.icon)) {
        throw ArgumentError('invalid UI contribution icon');
      }
    }
    if (ui.isNotEmpty &&
        !permissionSet.contains(PluginPermission.customUi.wireName)) {
      throw ArgumentError('UI contributions require customUi permission');
    }
  }

  static Set<String> _unique(String label, List<String> values) {
    final result = <String>{};
    for (final value in values) {
      if (value.isEmpty || !result.add(value)) {
        throw ArgumentError('invalid or duplicate $label: $value');
      }
    }
    return result;
  }

  static void _requireVersion(String label, String value) {
    if (!_versionPattern.hasMatch(value)) {
      throw ArgumentError('invalid $label: $value');
    }
  }

  static void requirePackagePath(String label, String value, String? suffix) {
    if (value.isEmpty ||
        value.startsWith('/') ||
        value.startsWith('\\') ||
        value.contains(':') ||
        value.contains('\\') ||
        value.contains('//')) {
      throw ArgumentError('invalid $label path: $value');
    }
    for (final segment in value.split('/')) {
      if (segment.isEmpty || segment == '.' || segment == '..') {
        throw ArgumentError('invalid $label path: $value');
      }
    }
    if (suffix != null && !value.toLowerCase().endsWith(suffix)) {
      throw ArgumentError('$label must end with $suffix');
    }
  }
}
