import 'package:flutter/material.dart';

import '../../core/app/app_controller.dart';
import '../../core/media/models.dart';
import '../../core/plugin/provider_capability.dart';
import '../widgets/cards.dart';
import '../widgets/cover_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/section_header.dart';
import 'details_page.dart';
import 'login_page.dart';
import 'plugins_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final feeds = controller.homeFeeds;
        final enabled = controller.enabledProviders;
        return RefreshIndicator(
          onRefresh: controller.refreshHome,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 130),
            children: [
              _BrandHeader(controller: controller),
              const SizedBox(height: 16),
              if (enabled.isEmpty)
                _NoSourceCard(
                  onOpenPlugins: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PluginsPage(controller: controller),
                    ),
                  ),
                )
              else ...[
                if (controller.homeLoading && feeds.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (!controller.homeLoading && feeds.isEmpty)
                  EmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: '暂时没有首页内容',
                    message: controller.homeError.isNotEmpty
                        ? controller.homeError
                        : '下拉刷新，或检查音源插件是否已启用。',
                    actionLabel: '重新加载',
                    onAction: controller.refreshHome,
                  ),
                for (final feed in feeds) _ProviderFeedView(
                  controller: controller,
                  feed: feed,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.tertiary,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.graphic_eq_rounded,
            color: theme.colorScheme.onPrimary,
            size: 28,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'zmusic',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                'qplug 音源驱动的音乐播放器',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '刷新首页',
          onPressed: () => controller.refreshHome(),
          icon: _RefreshIcon(spinning: controller.homeLoading),
        ),
      ],
    );
  }
}

class _NoSourceCard extends StatelessWidget {
  const _NoSourceCard({required this.onOpenPlugins});

  final VoidCallback onOpenPlugins;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.tertiaryContainer.withValues(alpha: 0.75),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.extension_rounded,
            size: 36,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(height: 14),
          Text(
            '先安装一个音源插件',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'zmusic 兼容官方 .qplug 插件。安装网易云、QQ 音乐等音源后，即可搜索、播放并同步账号。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onOpenPlugins,
            icon: const Icon(Icons.add_rounded),
            label: const Text('打开插件中心'),
          ),
        ],
      ),
    );
  }
}

class _ProviderFeedView extends StatelessWidget {
  const _ProviderFeedView({required this.controller, required this.feed});

  final AppController controller;
  final HomeProviderFeed feed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = controller.accountOf(feed.providerId) ?? feed.account;
    final canLogin = controller.supports(
      feed.providerId,
      ProviderCapability.login,
    );
    final sections = <Widget>[];

    if (feed.home.songs.isNotEmpty) {
      sections.add(_SongRail(
        controller: controller,
        providerId: feed.providerId,
        songs: feed.home.songs,
        title: '推荐歌曲',
      ));
    }
    if (feed.home.playlists.isNotEmpty) {
      sections.add(_PlaylistRail(
        controller: controller,
        title: '推荐歌单',
        playlists: feed.home.playlists,
      ));
    }
    for (final section in feed.home.sections) {
      sections.add(_PlaylistRail(
        controller: controller,
        title: section.title.isEmpty ? '歌单' : section.title,
        playlists: section.playlists,
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 2),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  feed.providerName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (account?.loggedIn ?? false)
                  _AccountChip(account: account!, onTap: () => _openLogin(
                        context,
                      ))
                else if (canLogin)
                  TextButton.icon(
                    onPressed: () => _openLogin(context),
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('登录'),
                  ),
              ],
            ),
          ),
          if (feed.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ErrorBanner(
                message: feed.error,
                onRetry: controller.refreshHome,
                title: '${feed.providerName} 加载失败',
              ),
            ),
          if (feed.error.isEmpty && sections.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '这个音源暂时没有首页推荐，试试搜索。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ...sections,
        ],
      ),
    );
  }

  void _openLogin(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/login'),
        builder: (_) => LoginPage(
          controller: controller,
          providerId: feed.providerId,
        ),
      ),
    );
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.account, required this.onTap});

  final AccountProfile account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.7,
          ),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CoverArt(
              url: account.avatarUrl,
              size: 26,
              radius: 13,
              icon: Icons.person_rounded,
            ),
            const SizedBox(width: 7),
            Text(
              account.displayName.isEmpty ? '已登录' : account.displayName,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongRail extends StatelessWidget {
  const _SongRail({
    required this.controller,
    required this.providerId,
    required this.songs,
    required this.title,
  });

  final AppController controller;
  final String providerId;
  final List<Song> songs;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        SizedBox(
          height: 214,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: songs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final song = songs[index];
              return _SongCard(
                song: song,
                onTap: () => controller.playback.playSongs(
                  songs,
                  index: index,
                  contextName: '$providerId 推荐',
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SongCard extends StatelessWidget {
  const _SongCard({required this.song, required this.onTap});

  final Song song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 148,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverArtFrame(
              url: song.artworkUrl,
              size: 148,
              radius: 18,
              icon: Icons.music_note_rounded,
            ),
            const SizedBox(height: 8),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              song.artistLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistRail extends StatelessWidget {
  const _PlaylistRail({
    required this.controller,
    required this.title,
    required this.playlists,
  });

  final AppController controller;
  final String title;
  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        SizedBox(
          height: 222,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: playlists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return PlaylistCard(
                playlist: playlist,
                subtitle: playlist.sourceName,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlaylistDetailPage(
                      controller: controller,
                      playlist: playlist,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// QPlayer's refresh affordance: the sync glyph turns while a reload is in
/// flight (700 ms per revolution) and rests at zero otherwise.
class _RefreshIcon extends StatefulWidget {
  const _RefreshIcon({required this.spinning});

  final bool spinning;

  @override
  State<_RefreshIcon> createState() => _RefreshIconState();
}

class _RefreshIconState extends State<_RefreshIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _RefreshIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.spinning && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: Tween<double>(begin: 1, end: 0).animate(_controller),
      child: const Icon(Icons.sync_rounded),
    );
  }
}
