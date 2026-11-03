import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app/app_controller.dart';
import '../../core/media/models.dart';
import '../widgets/cards.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_header.dart';
import '../widgets/song_tile.dart';
import 'details_page.dart';
import 'login_page.dart';

/// "我的" tab: the signed-in account, playlists owned by that account and the
/// locally recorded play history. Mirrors QPlayer's LibraryPage/AccountPage.
class MyPage extends StatefulWidget {
  const MyPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  List<Playlist> _playlists = const [];
  bool _loading = false;
  String _error = '';
  String _loadedSignature = '';

  AppController get _controller => widget.controller;

  String? get _providerId => _controller.primaryProviderId;

  String get _signature {
    final id = _providerId ?? '';
    final account = id.isEmpty ? null : _controller.accountOf(id);
    return [
      id,
      account?.loggedIn ?? false,
      account?.id ?? '',
      account?.displayName ?? '',
    ].join('|');
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _reload();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (_signature != _loadedSignature) _reload();
  }

  Future<void> _reload() async {
    final signature = _signature;
    _loadedSignature = signature;
    final id = _providerId;
    if (id == null || id.isEmpty) {
      if (mounted) {
        setState(() {
          _playlists = const [];
          _loading = false;
          _error = '';
        });
      }
      return;
    }
    final account = _controller.accountOf(id);
    if (account?.loggedIn != true) {
      if (mounted) {
        setState(() {
          _playlists = const [];
          _loading = false;
          _error = '';
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final lists = await _controller.myPlaylists(providerId: id);
      if (!mounted || signature != _signature) return;
      setState(() {
        _playlists = lists;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || signature != _signature) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _openLogin() async {
    final id = _providerId;
    if (id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/login'),
        builder: (_) => LoginPage(controller: _controller, providerId: id),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _logout() async {
    final id = _providerId;
    if (id == null) return;
    await _controller.logout(id);
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = _providerId;
    final account = id == null ? null : _controller.accountOf(id);
    final loggedIn = account?.loggedIn == true;
    final history = _controller.history.take(30).toList();
    final songs = history.map((entry) => entry.song).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 130),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '我的',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '账号、歌单与最近播放',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _AccountCard(
          providerId: id,
          providerName: id == null ? '' : _controller.providerName(id),
          account: account,
          onLogin: id == null ? null : _openLogin,
          onLogout: loggedIn ? _logout : null,
        ),
        if (id == null)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: EmptyState(
              icon: Icons.extension_off_rounded,
              title: '还没有可用的音源',
              message: '在设置中安装并启用一个音源插件后，这里会显示账号与歌单。',
              compact: true,
            ),
          ),
        if (id != null) ...[
          SectionHeader(
            title: '我的歌单',
            subtitle: loggedIn ? '来自 ${_controller.providerName(id)}' : '',
          ),
          if (!loggedIn)
            _HintCard(
              icon: Icons.lock_outline_rounded,
              text: '登录后同步歌单、收藏与账号信息。',
              actionLabel: '登录',
              onAction: _openLogin,
            )
          else if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error.isNotEmpty)
            _HintCard(
              icon: Icons.cloud_off_rounded,
              text: _error,
              actionLabel: '重试',
              onAction: _reload,
            )
          else if (_playlists.isEmpty)
            _HintCard(
              icon: Icons.queue_music_rounded,
              text: '这个账号还没有歌单。',
            )
          else
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final playlist in _playlists)
                  PlaylistCard(
                    playlist: playlist,
                    width: 160,
                    subtitle: playlist.owner?.name,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PlaylistDetailPage(
                          controller: _controller,
                          playlist: playlist,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          SectionHeader(
            title: '最近播放',
            subtitle: songs.isEmpty ? '' : '${songs.length} 首',
          ),
          if (songs.isEmpty)
            const _HintCard(
              icon: Icons.history_rounded,
              text: '播放过的歌曲会出现在这里。',
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < songs.length; i++) ...[
                    SongTile(
                      song: songs[i],
                      controller: _controller,
                      playback: _controller.playback,
                      isCurrent:
                          _controller.playback.currentSong?.id == songs[i].id,
                      onTap: () => _controller.playback.playSongs(
                        songs,
                        index: i,
                        contextName: '最近播放',
                      ),
                    ),
                    if (i != songs.length - 1)
                      const Divider(height: 1, indent: 64),
                  ],
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.providerId,
    required this.providerName,
    required this.account,
    required this.onLogin,
    required this.onLogout,
  });

  final String? providerId;
  final String providerName;
  final AccountProfile? account;
  final VoidCallback? onLogin;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loggedIn = account?.loggedIn == true;
    final name = account?.displayName.trim() ?? '';
    final details = <String>[
      if ((account?.membershipTier ?? 0) > 0) 'VIP ${account!.membershipTier}',
      if ((account?.level ?? 0) > 0) 'Lv.${account!.level}',
      if (providerName.isNotEmpty) providerName,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          _Avatar(url: loggedIn ? account?.avatarUrl ?? '' : ''),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loggedIn && name.isNotEmpty ? name : '未登录',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  loggedIn
                      ? (details.isEmpty ? '已登录' : details)
                      : (providerId == null
                          ? '安装音源插件后即可登录'
                          : '登录后同步歌单与收藏'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (loggedIn && (account?.signature.trim().isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      account!.signature,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (loggedIn)
            OutlinedButton(onPressed: onLogout, child: const Text('退出'))
          else if (onLogin != null)
            FilledButton(onPressed: onLogin, child: const Text('登录')),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: 68,
      height: 68,
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.person_rounded,
        size: 38,
        color: scheme.onSurfaceVariant,
      ),
    );
    Widget image;
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      image = Image.network(
        trimmed,
        width: 68,
        height: 68,
        fit: BoxFit.cover,
        cacheWidth: 160,
        cacheHeight: 160,
        errorBuilder: (_, _, _) => placeholder,
      );
    } else if (trimmed.isNotEmpty && File(trimmed).existsSync()) {
      image = Image.file(
        File(trimmed),
        width: 68,
        height: 68,
        fit: BoxFit.cover,
        cacheWidth: 160,
        cacheHeight: 160,
        errorBuilder: (_, _, _) => placeholder,
      );
    } else {
      image = placeholder;
    }
    return ClipOval(child: SizedBox(width: 68, height: 68, child: image));
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}
