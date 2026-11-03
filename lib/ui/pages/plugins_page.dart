import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app/app_controller.dart';
import '../../core/plugin/installed_plugin.dart';
import '../../core/plugin/plugin_catalog_service.dart';
import '../../core/plugin/plugin_package_verifier.dart';
import '../../core/plugin/plugin_permission.dart';
import '../../core/plugin/provider_capability.dart';
import '../widgets/app_toast.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_header.dart';

class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  List<CatalogRelease>? _releases;
  bool _loadingCatalog = false;
  String _catalogError = '';
  final Map<String, double> _progress = {};
  String _installing = '';
  bool _installingLocal = false;

  AppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    if (_loadingCatalog) return;
    setState(() {
      _loadingCatalog = true;
      _catalogError = '';
    });
    try {
      final releases = await _controller.plugins.catalogReleases();
      if (!mounted) return;
      setState(() {
        _releases = releases;
        _loadingCatalog = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _catalogError = e.toString();
        _loadingCatalog = false;
      });
    }
  }

  Future<void> _installLocal() async {
    if (_installingLocal) return;
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择 qplug 插件包',
      type: FileType.custom,
      allowedExtensions: const ['qplug'],
      allowMultiple: false,
    );
    final path = picked?.files.singleOrNull?.path;
    if (path == null) return;
    setState(() => _installingLocal = true);
    try {
      final verified = await PluginPackageVerifier().verify(
        path,
        allowUnsigned: true,
      );
      if (!mounted) return;
      final approved = await showDialog<Set<PluginPermission>>(
        context: context,
        builder: (_) => _PermissionDialog(
          pluginName: verified.manifest.name,
          version: verified.manifest.version,
          signed: verified.signed,
          permissions: verified.manifest.permissionSet.toList(),
        ),
      );
      if (approved == null) return;
      await _controller.plugins.installPackage(
        path,
        approvedPermissions: approved,
        allowUnsigned: true,
      );
      await _controller.refreshHome();
      if (!mounted) return;
      _snack('已安装 ${verified.manifest.name}');
      await _loadCatalog();
    } catch (e) {
      _snack('安装失败：$e');
    } finally {
      if (mounted) setState(() => _installingLocal = false);
    }
  }

  Future<void> _installCatalog(CatalogRelease release) async {
    if (_installing.isNotEmpty) return;
    setState(() {
      _installing = release.entry.id;
      _progress[release.entry.id] = 0;
    });
    try {
      await _controller.plugins.installFromCatalog(
        release,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() {
            _progress[release.entry.id] = received / total;
          });
        },
      );
      await _controller.refreshHome();
      if (!mounted) return;
      _snack('已安装 ${release.entry.name}');
      await _loadCatalog();
    } catch (e) {
      _snack('安装失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _installing = '';
          _progress.remove(release.entry.id);
        });
      }
    }
  }

  Future<void> _toggleEnabled(InstalledPlugin plugin, bool enabled) async {
    try {
      await _controller.plugins.setEnabled(plugin.id, enabled);
      if (!mounted) return;
      _snack(enabled ? '已启用 ${plugin.name}' : '已停用 ${plugin.name}');
      if (enabled) await _controller.refreshHome();
    } catch (e) {
      _snack('操作失败：$e');
    }
  }

  Future<void> _setPrimary(InstalledPlugin plugin) async {
    try {
      await _controller.plugins.setPrimary(plugin.id);
      if (!mounted) return;
      _snack('${plugin.name} 已设为主音源');
      await _controller.refreshHome();
    } catch (e) {
      _snack('操作失败：$e');
    }
  }

  Future<void> _remove(InstalledPlugin plugin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('卸载 ${plugin.name}？'),
        content: const Text(
          '将停止运行并删除插件文件。登录凭据与插件数据会保留，重新安装后可继续使用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _controller.plugins.remove(plugin.id);
      await _controller.refreshHome();
      if (!mounted) return;
      _snack('已卸载 ${plugin.name}');
    } catch (e) {
      _snack('卸载失败：$e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    AppToast.show(message);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller.plugins,
      builder: (context, _) {
        final theme = Theme.of(context);
        final installed = _controller.installedPlugins;
        final primary = _controller.plugins.primaryId;
        return Scaffold(
          appBar: AppBar(
            title: const Text('音源插件'),
            actions: [
              IconButton(
                tooltip: '刷新插件目录',
                onPressed: _loadingCatalog ? null : _loadCatalog,
                icon: _loadingCatalog
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.85),
                      theme.colorScheme.tertiaryContainer.withValues(alpha: 0.6),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.extension_rounded,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '官方 .qplug 兼容',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '插件在独立的 JavaScript 沙箱中运行，只有你批准的权限可用。安装包会校验哈希清单与发布者签名。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: _installingLocal ? null : _installLocal,
                          icon: _installingLocal
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.file_open_rounded),
                          label: const Text('从文件安装'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SectionHeader(
                title: '已安装',
                subtitle: '启用后可参与搜索、推荐与播放',
              ),
              if (installed.isEmpty)
                EmptyState(
                  icon: Icons.extension_off_rounded,
                  title: '还没有安装插件',
                  message: '从下方目录安装一个音源，或选择本地的 .qplug 文件。',
                  compact: true,
                  actionLabel: '从文件安装',
                  onAction: _installingLocal ? null : _installLocal,
                )
              else
                for (final plugin in installed)
                  _InstalledPluginCard(
                    plugin: plugin,
                    isPrimary: plugin.id == primary,
                    running: _controller.plugins.isRunning(plugin.id),
                    error: _controller.plugins.errorOf(plugin.id) ?? '',
                    onToggle: (value) => _toggleEnabled(plugin, value),
                    onPrimary: () => _setPrimary(plugin),
                    onRemove: () => _remove(plugin),
                  ),
              SectionHeader(
                title: '插件目录',
                subtitle: '来自固定 GitHub 仓库的签名发布',
                actionLabel: _loadingCatalog ? null : '刷新',
                onAction: _loadingCatalog ? null : _loadCatalog,
              ),
              if (_catalogError.isNotEmpty)
                ErrorBanner(message: _catalogError, onRetry: _loadCatalog),
              if (_releases == null && _loadingCatalog)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_releases != null)
                for (final release in _releases!)
                  _CatalogCard(
                    release: release,
                    busy: _installing == release.entry.id,
                    progress: _progress[release.entry.id],
                    disabled: _installing.isNotEmpty,
                    onInstall: () => _installCatalog(release),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _InstalledPluginCard extends StatelessWidget {
  const _InstalledPluginCard({
    required this.plugin,
    required this.isPrimary,
    required this.running,
    required this.error,
    required this.onToggle,
    required this.onPrimary,
    required this.onRemove,
  });

  final InstalledPlugin plugin;
  final bool isPrimary;
  final bool running;
  final String error;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPrimary;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPrimary =
        plugin.manifest.hasCapability(ProviderCapability.searchSongs);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.extension_rounded,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              plugin.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _Badge(
                            text: 'v${plugin.version}',
                            color: theme.colorScheme.secondaryContainer,
                            foreground: theme.colorScheme.onSecondaryContainer,
                          ),
                          if (isPrimary) ...[
                            const SizedBox(width: 5),
                            _Badge(
                              text: '主音源',
                              color: theme.colorScheme.primary,
                              foreground: theme.colorScheme.onPrimary,
                            ),
                          ],
                          if (plugin.signed) ...[
                            const SizedBox(width: 5),
                            Icon(
                              Icons.verified_rounded,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          plugin.manifest.publisher.isEmpty
                              ? '未知发布者'
                              : plugin.manifest.publisher,
                          if (plugin.manifest.capabilities.isNotEmpty)
                            '${plugin.manifest.capabilities.length} 项能力',
                          running ? '运行中' : '未运行',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: plugin.enabled,
                  onChanged: onToggle,
                ),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  onSelected: (value) {
                    switch (value) {
                      case 'primary':
                        onPrimary();
                      case 'permissions':
                        _showPermissions(context);
                      case 'remove':
                        onRemove();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'primary',
                      enabled: canPrimary && !isPrimary,
                      child: const Text('设为主音源'),
                    ),
                    const PopupMenuItem(
                      value: 'permissions',
                      child: Text('查看权限与能力'),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(
                        '卸载',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '运行错误：$error',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showPermissions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final permissions =
            plugin.permissions.map(PluginPermission.fromWireName).toList();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${plugin.name} 的权限',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (permissions.isEmpty)
                  Text(
                    '此插件没有申请额外权限。',
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final permission in permissions)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.check_circle_rounded,
                              color: theme.colorScheme.primary,
                            ),
                            title: Text(permission.label),
                            subtitle: Text(permission.description),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  '能力',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final capability in plugin.manifest.capabilities)
                      Chip(
                        label: Text(capability),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
    required this.release,
    required this.busy,
    required this.progress,
    required this.disabled,
    required this.onInstall,
  });

  final CatalogRelease release;
  final bool busy;
  final double? progress;
  final bool disabled;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installed = release.installedVersion.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    release.entry.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (installed)
                  _Badge(
                    text: release.updateAvailable ? '可更新' : '已安装',
                    color: release.updateAvailable
                        ? theme.colorScheme.tertiaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    foreground: release.updateAvailable
                        ? theme.colorScheme.onTertiaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              release.entry.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  release.tag.isEmpty ? release.entry.repo : release.tag,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (busy)
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      value: (progress ?? 0) > 0 ? progress : null,
                    ),
                  )
                else if (release.error.isNotEmpty)
                  Text(
                    '目录获取失败',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  )
                else
                  FilledButton.tonal(
                    onPressed: disabled ? null : onInstall,
                    child: Text(
                      !installed
                          ? '安装'
                          : (release.updateAvailable ? '更新' : '重装'),
                    ),
                  ),
              ],
            ),
            if (release.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  release.error,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.color,
    required this.foreground,
  });

  final String text;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _PermissionDialog extends StatefulWidget {
  const _PermissionDialog({
    required this.pluginName,
    required this.version,
    required this.signed,
    required this.permissions,
  });

  final String pluginName;
  final String version;
  final bool signed;
  final List<PluginPermission> permissions;

  @override
  State<_PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<_PermissionDialog> {
  late final Set<PluginPermission> _approved = {...widget.permissions};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allApproved = _approved.length == widget.permissions.length;
    return AlertDialog(
      title: Text('安装 ${widget.pluginName}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    widget.signed
                        ? Icons.verified_user_rounded
                        : Icons.warning_amber_rounded,
                    color: widget.signed
                        ? theme.colorScheme.primary
                        : theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.signed
                          ? '签名校验通过 · v${widget.version}'
                          : '未签名安装包 · v${widget.version}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: widget.signed
                            ? theme.colorScheme.primary
                            : theme.colorScheme.tertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.permissions.isEmpty
                    ? '此插件没有申请额外权限。'
                    : '该插件申请以下权限，全部批准后才能启用：',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              for (final permission in widget.permissions)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _approved.contains(permission),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _approved.add(permission);
                      } else {
                        _approved.remove(permission);
                      }
                    });
                  },
                  title: Text(permission.label),
                  subtitle: Text(permission.description),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: allApproved
              ? () => Navigator.of(context).pop(Set.of(_approved))
              : null,
          child: const Text('全部批准并安装'),
        ),
      ],
    );
  }
}
