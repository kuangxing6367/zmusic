import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../media/models.dart';
import 'host/host_api.dart';
import 'installed_plugin.dart';
import 'plugin_catalog_service.dart';
import 'plugin_manifest.dart';
import 'plugin_package_verifier.dart';
import 'plugin_permission.dart';
import 'plugin_provider_service.dart';
import 'plugin_registry.dart';
import 'plugin_runtime.dart';
import 'provider_capability.dart';

class PluginManager extends ChangeNotifier {
  PluginManager({
    required this.registry,
    required this.pluginsRoot,
    required this.dataRoot,
  });

  final PluginRegistry registry;
  final Directory pluginsRoot;
  final Directory dataRoot;

  final PluginPackageVerifier _verifier = PluginPackageVerifier();
  final PluginCatalogService catalog = PluginCatalogService();
  final Map<String, PluginRuntime> _runtimes = {};
  final Map<String, String> _errors = {};
  final Map<String, AccountProfile> _accounts = {};
  late final PluginProviderService providers;
  late final CorePluginHostApi hostApi;
  PluginAppBridge? _bridge;
  bool _initialized = false;

  bool get initialized => _initialized;

  void attachAppBridge(PluginAppBridge bridge) => _bridge = bridge;

  Future<void> initialize() async {
    final bridge = _bridge;
    if (bridge == null) {
      throw StateError('attachAppBridge must be called before initialize');
    }
    hostApi = CorePluginHostApi(
      storageRoot: dataRoot,
      manifestOf: _manifestOf,
      appBridge: bridge,
    );
    providers = PluginProviderService(
      manifestOf: _manifestOf,
      runtimeOf: _runtimeOf,
    );
    await registry.load();
    await _startEnabled();
    _initialized = true;
    notifyListeners();
  }

  PluginManifest? _manifestOf(String id) {
    final entry = registry.get(id);
    if (entry == null || !entry.enabled) return null;
    return entry.manifest;
  }

  PluginRuntime? _runtimeOf(String id) => _runtimes[id];

  Future<void> _startEnabled() async {
    for (final entry in registry.enabled) {
      try {
        await _start(entry);
      } catch (e) {
        _errors[entry.id] = e.toString();
        debugPrint('plugin ${entry.id} failed to start: $e');
      }
    }
  }

  Future<void> _start(InstalledPlugin entry) async {
    if (_runtimes.containsKey(entry.id)) return;
    final root = Directory(entry.directory);
    if (!await root.exists()) {
      throw PluginExecutionException('插件目录不存在');
    }
    final runtime = PluginRuntime(
      root: root,
      manifest: entry.manifest,
      hostCall: (pluginId, method, args) =>
          hostApi.call(pluginId, method, args),
    );
    await runtime.start(
      backgroundTicks: entry.manifest.hasPermission(
        PluginPermission.backgroundTimers,
      ),
    );
    _runtimes[entry.id] = runtime;
    _errors.remove(entry.id);
  }

  Future<void> _stop(String id) async {
    final runtime = _runtimes.remove(id);
    runtime?.close();
  }

  String? errorOf(String id) => _errors[id];

  bool isRunning(String id) => _runtimes[id]?.isRunning ?? false;

  List<InstalledPlugin> get installed => registry.plugins;

  InstalledPlugin? entry(String id) => registry.get(id);

  List<String> get enabledProviderIds => registry.enabled
      .where((plugin) => _runtimes.containsKey(plugin.id))
      .map((plugin) => plugin.id)
      .toList();

  String? get primaryId {
    final primary = registry.primary;
    if (primary != null && _runtimes.containsKey(primary.id)) {
      return primary.id;
    }
    final enabled = enabledProviderIds;
    return enabled.isEmpty ? null : enabled.first;
  }

  InstalledPlugin? get primaryEntry {
    final id = primaryId;
    return id == null ? null : registry.get(id);
  }

  /// Providers that can run a global song search, primary first.
  List<String> get searchProviders {
    final ids = enabledProviderIds.where((id) {
      final manifest = registry.get(id)?.manifest;
      return manifest?.hasCapability(ProviderCapability.searchSongs) ?? false;
    }).toList();
    final primary = primaryId;
    if (primary != null && ids.remove(primary)) ids.insert(0, primary);
    return ids;
  }

  AccountProfile? accountOf(String id) => _accounts[id];

  Future<AccountProfile> refreshAccount(String id) async {
    final profile = await providers.account(id);
    _accounts[id] = profile;
    notifyListeners();
    return profile;
  }

  /// Installs a verified package. Returns the installed entry.
  Future<InstalledPlugin> installPackage(
    String path, {
    required Set<PluginPermission> approvedPermissions,
    String? publisherKeyBase64,
    bool allowUnsigned = true,
    bool enable = true,
  }) async {
    final verified = await _verifier.verify(
      path,
      publisherKeyBase64: publisherKeyBase64,
      allowUnsigned: allowUnsigned,
    );
    final manifest = verified.manifest;
    if (!approvedPermissions.containsAll(manifest.permissionSet)) {
      throw PluginPackageException('并非所有插件权限都已批准');
    }

    final pluginRoot = Directory(
        '${pluginsRoot.path}${Platform.pathSeparator}${manifest.id}');
    final target = Directory(
        '${pluginRoot.path}${Platform.pathSeparator}${manifest.version}');
    final existing = registry.get(manifest.id);
    if (await target.exists()) {
      if (existing != null &&
          existing.version == manifest.version &&
          existing.packageDigest == verified.packageDigest) {
        await registry.upsert(existing.copyWith(
          enabled: enable,
          permissions: manifest.permissions,
        ));
        if (enable) {
          await _start(registry.get(manifest.id)!);
        }
        notifyListeners();
        return registry.get(manifest.id)!;
      }
      throw PluginPackageException('同一版本已存在不同的插件包');
    }

    await target.create(recursive: true);
    try {
      for (final file in verified.files.entries) {
        final output = File(
            '${target.path}${Platform.pathSeparator}'
            '${file.key.replaceAll('/', Platform.pathSeparator)}');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(file.value, flush: true);
      }
      await File('${target.path}${Platform.pathSeparator}.qplayer-install.json')
          .writeAsString(jsonEncode({
        'schemaVersion': 1,
        'packageDigest': verified.packageDigest,
        'signed': verified.signed,
        'hashes': verified.hashes,
      }), flush: true);

      // Preflight: parse and initialize the exact staged JavaScript with host
      // calls denied, so installation cannot perform side effects.
      final preflight = PluginRuntime(
        root: target,
        manifest: manifest,
        hostCall: (pluginId, method, arguments) =>
            Future.error(StateError('host calls are disabled during preflight')),
      );
      try {
        await preflight.start();
      } finally {
        preflight.close();
      }

      final entry = InstalledPlugin(
        manifest: manifest,
        directory: target.path,
        enabled: enable,
        primary: registry.primary == null && manifest.hasCapability(
              ProviderCapability.searchSongs,
            ),
        signed: verified.signed,
        packageDigest: verified.packageDigest,
        permissions: manifest.permissions,
        installedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await registry.upsert(entry);
      if (enable) await _start(entry);
      notifyListeners();
      return entry;
    } catch (e) {
      try {
        await target.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }

  Future<InstalledPlugin> installFromCatalog(
    CatalogRelease release, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (release.downloadUrl.isEmpty) {
      throw PluginPackageException('该插件没有可下载的安装包');
    }
    final temp = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'qplayer-${release.entry.id}-${DateTime.now().microsecondsSinceEpoch}.qplug');
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          headers: {'User-Agent': 'QPlayer-Flutter'},
        ),
      );
      await _downloadWithMirrors(dio, release.downloadUrl, temp.path, onProgress);
      final verified = await _verifier.verify(
        temp.path,
        publisherKeyBase64: release.entry.publisherKey,
        allowUnsigned: false,
      );
      if (verified.manifest.id != release.entry.id) {
        throw PluginPackageException('插件 ID 与目录条目不匹配');
      }
      final installed = await installPackage(
        temp.path,
        approvedPermissions: verified.manifest.permissionSet,
        publisherKeyBase64: release.entry.publisherKey,
        allowUnsigned: false,
      );
      await refreshAccountIfSupported(installed.id);
      return installed;
    } finally {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
    }
  }

  /// GitHub release assets are frequently unreachable from mainland China.
  /// Mirrors are tried after the direct URL; the package signature check below
  /// still guarantees the bytes came from the pinned publisher.
  static const List<String> _downloadMirrors = <String>[
    '',
    'https://ghfast.top/',
    'https://gh-proxy.com/',
  ];

  Future<void> _downloadWithMirrors(
    Dio dio,
    String url,
    String path,
    void Function(int received, int total)? onProgress,
  ) async {
    Object? lastError;
    for (final prefix in _downloadMirrors) {
      final target = prefix.isEmpty ? url : '$prefix$url';
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
        await dio
            .download(
              target,
              path,
              options: Options(receiveTimeout: const Duration(seconds: 45)),
              onReceiveProgress: onProgress,
            )
            .timeout(const Duration(seconds: 90));
        if (await file.exists() && await file.length() > 0) return;
        lastError = '下载到的安装包为空';
      } catch (error) {
        lastError = error;
      }
    }
    throw PluginPackageException('安装包下载失败：$lastError');
  }

  Future<void> refreshAccountIfSupported(String id) async {
    final manifest = registry.get(id)?.manifest;
    if (manifest == null || !manifest.hasCapability(ProviderCapability.account)) {
      return;
    }
    try {
      await refreshAccount(id);
    } catch (_) {
      // Login state is optional; failures are surfaced by the account page.
    }
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await registry.setEnabled(id, enabled);
    if (enabled) {
      final entry = registry.get(id);
      if (entry != null) {
        try {
          await _start(entry);
          await refreshAccountIfSupported(id);
        } catch (e) {
          _errors[id] = e.toString();
        }
      }
    } else {
      await _stop(id);
    }
    notifyListeners();
  }

  Future<void> setPrimary(String id) async {
    await registry.setPrimary(id);
    final entry = registry.get(id);
    if (entry != null && !entry.enabled) {
      await setEnabled(id, true);
    }
    notifyListeners();
  }

  Future<void> remove(String id) async {
    await _stop(id);
    final entry = registry.get(id);
    if (entry != null) {
      final pluginRoot = Directory(
          '${pluginsRoot.path}${Platform.pathSeparator}$id');
      try {
        if (await pluginRoot.exists()) {
          await pluginRoot.delete(recursive: true);
        }
      } catch (e) {
        debugPrint('failed to delete plugin files: $e');
      }
    }
    await registry.remove(id);
    _accounts.remove(id);
    _errors.remove(id);
    // Credentials and plugin data are intentionally retained for reinstall.
    notifyListeners();
  }

  Future<List<CatalogRelease>> catalogReleases() async {
    final installedVersions = {
      for (final plugin in registry.plugins) plugin.id: plugin.version,
    };
    return catalog.releases(installedVersions: installedVersions);
  }

  Future<Map<String, dynamic>> openUiDialog(
    String provider,
    String contributionId,
    String action,
    Map<String, dynamic> inputs,
  ) {
    return providers.invokeUi(provider, contributionId, action, inputs);
  }

  Future<String> packageDigestOf(String id) async {
    final entry = registry.get(id);
    if (entry == null) return '';
    final receipt = File(
        '${entry.directory}${Platform.pathSeparator}.qplayer-install.json');
    if (!await receipt.exists()) return entry.packageDigest;
    try {
      final raw = jsonDecode(await receipt.readAsString());
      return raw['packageDigest']?.toString() ?? entry.packageDigest;
    } catch (_) {
      return entry.packageDigest;
    }
  }

  @override
  void dispose() {
    for (final runtime in _runtimes.values) {
      runtime.close();
    }
    _runtimes.clear();
    super.dispose();
  }
}
