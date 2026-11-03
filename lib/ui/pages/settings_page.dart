import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app/app_controller.dart';
import '../../core/app/appearance_settings.dart';
import '../../core/playback/playback_controller.dart';
import '../icon_map.dart';
import '../widgets/section_header.dart';
import '../widgets/smooth_scroll.dart';
import 'plugin_dialog_page.dart';
import 'plugins_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        controller,
        controller.plugins,
        controller.lyricSettings,
        controller.appearance,
      ]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final playback = controller.playback;
        final lyrics = controller.lyricSettings;
        return SmoothScrollList(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 130),
          children: [
            Text(
              '设置',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '外观、播放与插件管理',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SectionHeader(title: '外观'),
            _SettingsCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '主题模式',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'system',
                            icon: Icon(Icons.brightness_auto_rounded),
                            label: Text('跟随系统'),
                          ),
                          ButtonSegment(
                            value: 'light',
                            icon: Icon(Icons.light_mode_rounded),
                            label: Text('浅色'),
                          ),
                          ButtonSegment(
                            value: 'dark',
                            icon: Icon(Icons.dark_mode_rounded),
                            label: Text('深色'),
                          ),
                        ],
                        selected: {controller.themeMode},
                        showSelectedIcon: false,
                        onSelectionChanged: (value) =>
                            controller.setThemeMode(value.first),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '主题色',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '影响按钮、高亮与歌词扫色',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SeedColorPicker(settings: controller.appearance),
                    ],
                  ),
                ),
                const Divider(height: 1),
                _BackdropSettings(controller: controller),
                const SizedBox(height: 10),
              ],
            ),
            const SectionHeader(
              title: '歌词',
              subtitle: '播放页与桌面歌词的外观',
            ),
            _SettingsCard(
              children: [
                _LyricSlider(
                  title: '歌词字号',
                  value: lyrics.fontSize,
                  min: 14,
                  max: 40,
                  divisions: 26,
                  label: '${lyrics.fontSize.round()} px',
                  onChanged: lyrics.setFontSize,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '字重',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SegmentedButton<int>(
                            segments: const [
                              ButtonSegment(value: 300, label: Text('细')),
                              ButtonSegment(value: 400, label: Text('轻')),
                              ButtonSegment(value: 500, label: Text('常规')),
                              ButtonSegment(value: 600, label: Text('中等')),
                            ],
                            selected: {lyrics.fontWeightValue},
                            showSelectedIcon: false,
                            onSelectionChanged: (value) =>
                                lyrics.setFontWeight(value.first),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                _LyricSlider(
                  title: '行距',
                  value: lyrics.lineSpacing,
                  min: 1.1,
                  max: 2.4,
                  divisions: 26,
                  label: '${(lyrics.lineSpacing * 100).round()}%',
                  onChanged: lyrics.setLineSpacing,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.font_download_rounded),
                  title: const Text('歌词字体'),
                  trailing: DropdownButton<String>(
                    value: lyrics.fontFamily,
                    underline: const SizedBox.shrink(),
                    borderRadius: BorderRadius.circular(14),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('系统默认')),
                      DropdownMenuItem(
                        value: 'Microsoft YaHei UI',
                        child: Text('微软雅黑'),
                      ),
                      DropdownMenuItem(value: 'SimSun', child: Text('宋体')),
                      DropdownMenuItem(value: 'KaiTi', child: Text('楷体')),
                      DropdownMenuItem(value: 'DengXian', child: Text('等线')),
                    ],
                    onChanged: (value) {
                      if (value != null) lyrics.setFontFamily(value);
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '对齐',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'duet', label: Text('对唱')),
                              ButtonSegment(value: 'left', label: Text('左')),
                              ButtonSegment(value: 'center', label: Text('中')),
                              ButtonSegment(value: 'right', label: Text('右')),
                            ],
                            selected: {lyrics.alignment},
                            showSelectedIcon: false,
                            onSelectionChanged: (value) =>
                                lyrics.setAlignment(value.first),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12),
                  secondary: const Icon(Icons.translate_rounded),
                  title: const Text('显示翻译'),
                  value: lyrics.showTranslation,
                  onChanged: lyrics.setShowTranslation,
                ),
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12),
                  secondary: const Icon(Icons.abc_rounded),
                  title: const Text('显示罗马音'),
                  value: lyrics.showRomanization,
                  onChanged: lyrics.setShowRomanization,
                ),
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12),
                  secondary: const Icon(Icons.blur_on_rounded),
                  title: const Text('歌词阴影'),
                  subtitle: const Text('深色封面背景下更易读'),
                  value: lyrics.shadow,
                  onChanged: lyrics.setShadow,
                ),
                const Divider(height: 1),
                _LyricSlider(
                  title: '桌面歌词字号',
                  value: lyrics.desktopFontSize,
                  min: 18,
                  max: 38,
                  divisions: 20,
                  label: '${lyrics.desktopFontSize.round()} px',
                  onChanged: lyrics.setDesktopFontSize,
                ),
                _LyricSlider(
                  title: '桌面歌词背景',
                  value: lyrics.desktopBackgroundOpacity,
                  min: 0,
                  max: 0.9,
                  divisions: 18,
                  label:
                      '${(lyrics.desktopBackgroundOpacity * 100).round()}%',
                  onChanged: lyrics.setDesktopBackgroundOpacity,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12),
                  secondary: const Icon(Icons.smartphone_rounded),
                  title: const Text('状态栏歌词'),
                  subtitle: const Text('手机端在顶部以灵动岛样式显示当前歌词'),
                  value: lyrics.showIsland,
                  onChanged: lyrics.setShowIsland,
                ),
              ],
            ),
            const SectionHeader(title: '播放'),
            _SettingsCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.high_quality_rounded),
                  title: const Text('音质'),
                  subtitle: const Text('插件会按此偏好请求音频流'),
                  trailing: DropdownButton<String>(
                    value: controller.quality,
                    underline: const SizedBox.shrink(),
                    borderRadius: BorderRadius.circular(14),
                    items: [
                      for (final entry in AppController.qualityLabels.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) controller.setQuality(value);
                    },
                  ),
                ),
                const Divider(height: 1),
                _SleepTile(playback: playback),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: const Text('最近播放'),
                  subtitle: Text('${controller.history.length} 条记录'),
                  trailing: TextButton(
                    onPressed: controller.history.isEmpty
                        ? null
                        : () => _confirmHistory(context),
                    child: const Text('清空'),
                  ),
                ),
              ],
            ),
            const SectionHeader(title: '本地音乐'),
            _SettingsCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: const Text('音乐文件夹'),
                  subtitle: Text(
                    '${controller.library.folders.length} 个文件夹 · '
                    '${controller.library.songs.length} 首歌曲',
                  ),
                  trailing: TextButton(
                    onPressed: controller.library.isEmpty
                        ? null
                        : () => _confirmLibrary(context),
                    child: const Text('清除'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.sync_rounded),
                  title: const Text('重新扫描'),
                  subtitle: const Text('读取新增或修改过的音乐文件'),
                  trailing: controller.library.scanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: controller.library.scanning
                      ? null
                      : () => controller.library.scan(),
                ),
              ],
            ),
            const SectionHeader(
              title: '音源插件',
              subtitle: '安装、启用与权限管理',
            ),
            _SettingsCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.extension_rounded),
                  title: const Text('插件管理'),
                  subtitle: Text(
                    '${controller.installedPlugins.length} 个已安装 · '
                    '${controller.enabledProviders.length} 个运行中',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PluginsPage(controller: controller),
                    ),
                  ),
                ),
                ..._pluginSettingsEntries(context),
              ],
            ),
            const SectionHeader(title: '关于'),
            _SettingsCard(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('zmusic'),
                  subtitle: Text('Flutter 重写的 QPlayer · 兼容官方 .qplug 插件'),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.shield_outlined),
                  title: Text('插件安全'),
                  subtitle: Text(
                    'SHA-256 清单校验 · P-256 签名 · JavaScript 沙箱 · 权限门控',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.code_rounded),
                  title: const Text('版本'),
                  subtitle: const Text('1.0.0 · 宿主 ABI 1.9.7'),
                  trailing: Text(
                    'api 1.0',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  List<Widget> _pluginSettingsEntries(BuildContext context) {
    final tiles = <Widget>[];
    for (final plugin in controller.installedPlugins) {
      if (!plugin.enabled) continue;
      for (final contribution in plugin.manifest.ui) {
        if (contribution.placement != 'settings') continue;
        tiles.add(const Divider(height: 1));
        tiles.add(
          ListTile(
            leading: Icon(iconForName(contribution.icon)),
            title: Text(
              contribution.label.isEmpty ? plugin.name : contribution.label,
            ),
            subtitle: Text(plugin.name),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PluginDialogPage(
                  controller: controller,
                  providerId: plugin.id,
                  contributionId: contribution.id,
                  label: contribution.label,
                  icon: contribution.icon,
                ),
              ),
            ),
          ),
        );
      }
    }
    return tiles;
  }

  Future<void> _confirmHistory(BuildContext context) async {
    final ok = await _confirm(
      context,
      title: '清空最近播放？',
      message: '只会删除本机的播放历史，不会影响平台账号。',
      action: '清空',
    );
    if (ok) controller.clearHistory();
  }

  Future<void> _confirmLibrary(BuildContext context) async {
    final ok = await _confirm(
      context,
      title: '清除本地曲库？',
      message: '会移除所有文件夹设置与扫描缓存，不会删除磁盘上的音乐文件。',
      action: '清除',
    );
    if (ok) controller.library.clear();
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 2),
      child: Column(children: children),
    );
  }
}

class _SleepTile extends StatefulWidget {
  const _SleepTile({required this.playback});

  final PlaybackController playback;

  @override
  State<_SleepTile> createState() => _SleepTileState();
}

class _SleepTileState extends State<_SleepTile> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.playback.sleepDeadline != null && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deadline = widget.playback.sleepDeadline;
    String subtitle = '到点后自动暂停播放';
    if (deadline != null) {
      final remaining = deadline.difference(DateTime.now());
      final seconds = remaining.inSeconds.clamp(0, 24 * 60 * 60);
      subtitle = '还剩 ${(seconds ~/ 60).toString().padLeft(2, '0')}:'
          '${(seconds % 60).toString().padLeft(2, '0')}';
    }
    return ListTile(
      leading: const Icon(Icons.bedtime_rounded),
      title: const Text('定时暂停'),
      subtitle: Text(subtitle),
      trailing: PopupMenuButton<String>(
        tooltip: '定时暂停',
        onSelected: (value) {
          widget.playback.setSleepTimer(switch (value) {
            '15' => const Duration(minutes: 15),
            '30' => const Duration(minutes: 30),
            '60' => const Duration(minutes: 60),
            _ => null,
          });
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: '15', child: Text('15 分钟')),
          PopupMenuItem(value: '30', child: Text('30 分钟')),
          PopupMenuItem(value: '60', child: Text('60 分钟')),
          PopupMenuItem(value: 'off', child: Text('关闭')),
        ],
        child: const Icon(Icons.timer_outlined),
      ),
    );
  }
}

class _SeedColorPicker extends StatelessWidget {
  const _SeedColorPicker({required this.settings});

  final AppearanceSettings settings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final color in AppearanceSettings.seedPresets)
          _SeedSwatch(
            color: color,
            selected: color.toARGB32() == settings.seedColor.toARGB32(),
            onTap: () => settings.setSeedColor(color),
            outline: scheme.onSurface,
          ),
      ],
    );
  }
}

class _SeedSwatch extends StatelessWidget {
  const _SeedSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
    required this.outline,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? outline : Colors.transparent,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: selected ? 0.45 : 0.18),
                blurRadius: selected ? 14 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: selected
              ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

class _BackdropSettings extends StatefulWidget {
  const _BackdropSettings({required this.controller});

  final AppController controller;

  @override
  State<_BackdropSettings> createState() => _BackdropSettingsState();
}

class _BackdropSettingsState extends State<_BackdropSettings> {
  late final TextEditingController _url =
      TextEditingController(text: widget.controller.appearance.backdropUrl);

  AppearanceSettings get _settings => widget.controller.appearance;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = _settings.backdropSource;
    final showImageControls = source != BackdropSource.none;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '页面背景',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (source == BackdropSource.bing ||
                  source == BackdropSource.furry)
                TextButton.icon(
                  onPressed: _settings.shuffleBackdrop,
                  icon: const Icon(Icons.casino_rounded, size: 18),
                  label: const Text('换一张'),
                ),
            ],
          ),
          Text(
            '模糊背景会铺在首页、搜索、我的与设置页后面',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in const {
                BackdropSource.none: '关闭',
                BackdropSource.cover: '当前封面',
                BackdropSource.bing: '必应每日',
                BackdropSource.furry: '随机插画',
                BackdropSource.custom: '自定义',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: source == entry.key,
                  onSelected: (_) => _settings.setBackdropSource(entry.key),
                ),
            ],
          ),
          if (source == BackdropSource.custom) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: '图片链接',
                hintText: 'https://example.com/wallpaper.jpg',
                isDense: true,
              ),
              onSubmitted: _settings.setBackdropUrl,
              onTapOutside: (_) {
                _settings.setBackdropUrl(_url.text);
                FocusScope.of(context).unfocus();
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  _settings.setBackdropUrl(_url.text);
                  FocusScope.of(context).unfocus();
                },
                child: const Text('应用链接'),
              ),
            ),
          ],
          if (showImageControls) ...[
            const SizedBox(height: 4),
            _LyricSlider(
              title: '模糊',
              value: _settings.backdropBlur,
              min: 0,
              max: 60,
              divisions: 30,
              label: _settings.backdropBlur.round().toString(),
              onChanged: _settings.setBackdropBlur,
            ),
            _LyricSlider(
              title: '不透明度',
              value: _settings.backdropOpacity,
              min: 0.05,
              max: 0.85,
              divisions: 16,
              label: '${(_settings.backdropOpacity * 100).round()}%',
              onChanged: _settings.setBackdropOpacity,
            ),
          ],
        ],
      ),
    );
  }
}


class _LyricSlider extends StatelessWidget {
  const _LyricSlider({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
