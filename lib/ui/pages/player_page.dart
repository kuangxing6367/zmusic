import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide RepeatMode;

import 'package:flutter/services.dart';

import '../../core/app/app_controller.dart';
import '../../core/app/desktop_lyric_service.dart';
import '../../core/media/models.dart';
import '../../core/playback/playback_controller.dart';
import '../../core/plugin/provider_capability.dart';
import '../icon_map.dart';
import '../theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/cards.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/queue_sheet.dart';
import 'plugin_dialog_page.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  String _likedSongId = '';
  bool _liked = false;
  bool _coverMode = false;
  bool _offsetOpen = false;
  DesktopLyricService? _lyricsService;

  PlaybackController get _playback => widget.controller.playback;

  @override
  void initState() {
    super.initState();
    _lyricsService = DesktopLyricService.instance;
    _lyricsService?.addListener(_onLyricsServiceChanged);
    _scheduleLikeSync();
  }

  void _onLyricsServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _lyricsService?.removeListener(_onLyricsServiceChanged);
    super.dispose();
  }

  void _scheduleLikeSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncLike();
    });
  }

  Future<void> _syncLike() async {
    final song = _playback.currentSong;
    if (song == null) {
      if (_likedSongId.isNotEmpty) {
        setState(() {
          _likedSongId = '';
          _liked = false;
        });
      }
      return;
    }
    if (song.id == _likedSongId) return;
    _likedSongId = song.id;
    _liked = false;
    if (song.mediaId == null ||
        !widget.controller.supports(song.provider, ProviderCapability.like)) {
      if (mounted) setState(() {});
      return;
    }
    try {
      final liked = await widget.controller.likedSongs(song.provider);
      if (!mounted || _likedSongId != song.id) return;
      setState(() => _liked = liked.contains(song.mediaId.toString()));
    } catch (_) {
      // Liking is optional; the button simply stays unset.
    }
  }

  Future<void> _toggleLike() async {
    final song = _playback.currentSong;
    if (song == null || song.mediaId == null) return;
    if (!widget.controller.supports(song.provider, ProviderCapability.like)) {
      _snack('该音源不支持喜欢歌曲');
      return;
    }
    final target = !_liked;
    try {
      final ok = await widget.controller.setLiked(song, target);
      if (!mounted) return;
      if (ok) {
        setState(() => _liked = target);
        _snack(target ? '已喜欢' : '已取消喜欢');
      } else {
        _snack('操作失败');
      }
    } catch (e) {
      _snack('操作失败：$e');
    }
  }

  void _toggleDesktopLyrics() {
    final service = DesktopLyricService.instance;
    if (service == null) {
      _snack('桌面歌词尚未就绪');
      return;
    }
    service.toggle();
  }

  void _snack(String message) {
    if (!mounted) return;
    AppToast.show(message);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0B10),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          leading: IconButton(
            tooltip: '收起',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
          ),
          title: const Text('正在播放', style: TextStyle(fontSize: 15)),
          centerTitle: true,
          actions: [
            ..._pluginActions(),
            if (Platform.isWindows)
              IconButton(
                tooltip: '桌面歌词',
                onPressed: _toggleDesktopLyrics,
                icon: Icon(
                  Icons.subtitles_rounded,
                  color: _lyricsService?.visible == true
                      ? const Color(0xFF82B1FF)
                      : null,
                ),
              ),
            IconButton(
              tooltip: _coverMode ? '显示歌词' : '显示封面',
              onPressed: () => setState(() => _coverMode = !_coverMode),
              icon: Icon(
                _coverMode ? Icons.lyrics_rounded : Icons.image_rounded,
              ),
            ),
            IconButton(
              tooltip: '歌词偏移',
              onPressed: () => setState(() => _offsetOpen = !_offsetOpen),
              icon: const Icon(Icons.sync_rounded),
            ),
            PopupMenuButton<String>(
              tooltip: '更多',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: _onMenu,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'queue',
                  child: ListTile(
                    leading: Icon(Icons.queue_music_rounded),
                    title: Text('播放队列'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'like',
                  child: ListTile(
                    leading: Icon(Icons.favorite_rounded),
                    title: Text('喜欢歌曲'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                    leading: Icon(Icons.ios_share_rounded),
                    title: Text('分享'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'download',
                  child: ListTile(
                    leading: Icon(Icons.download_rounded),
                    title: Text('下载当前歌曲'),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'offset-m',
                  child: ListTile(
                    leading: Icon(Icons.remove_rounded),
                    title: Text('歌词延迟 0.5 秒'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'offset-r',
                  child: ListTile(
                    leading: Icon(Icons.restart_alt_rounded),
                    title: Text('歌词偏移重置'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'offset-p',
                  child: ListTile(
                    leading: Icon(Icons.add_rounded),
                    title: Text('歌词提前 0.5 秒'),
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'sleep-15',
                  child: ListTile(
                    leading: Icon(Icons.bedtime_rounded),
                    title: Text('15 分钟后暂停'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'sleep-30',
                  child: ListTile(
                    leading: Icon(Icons.bedtime_rounded),
                    title: Text('30 分钟后暂停'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'sleep-60',
                  child: ListTile(
                    leading: Icon(Icons.bedtime_rounded),
                    title: Text('60 分钟后暂停'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'sleep-off',
                  child: ListTile(
                    leading: Icon(Icons.timer_off_rounded),
                    title: Text('取消定时暂停'),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: AnimatedBuilder(
          animation: Listenable.merge([
            _playback,
            widget.controller.lyricSettings,
          ]),
          builder: (context, _) {
            final song = _playback.currentSong;
            if (song != null && song.id != _likedSongId) {
              _scheduleLikeSync();
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                _Backdrop(song: song),
                SafeArea(
                  child: song == null
                      ? const Center(
                          child: Text(
                            '还没有正在播放的歌曲',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 880;
                            return wide
                                ? _WideLayout(
                                    controller: widget.controller,
                                    song: song,
                                    liked: _liked,
                                    onToggleLike: _toggleLike,
                                    onSnack: _snack,
                                  )
                                : _NarrowLayout(
                                    controller: widget.controller,
                                    song: song,
                                    liked: _liked,
                                    onToggleLike: _toggleLike,
                                    onSnack: _snack,
                                  );
                          },
                        ),
                ),
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    reverseDuration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final scale = Tween<double>(begin: 0.94, end: 1).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      );
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: scale, child: child),
                      );
                    },
                    child: _coverMode && song != null
                        ? _CoverModeOverlay(
                            key: const ValueKey('cover-mode'),
                            controller: widget.controller,
                            onClose: () =>
                                setState(() => _coverMode = false),
                          )
                        : const SizedBox.shrink(key: ValueKey('lyrics-mode')),
                  ),
                ),
                if (_offsetOpen)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => setState(() => _offsetOpen = false),
                    ),
                  ),
                Positioned(
                  top: 60,
                  right: 16,
                  child: IgnorePointer(
                    ignoring: !_offsetOpen,
                    child: AnimatedOpacity(
                      opacity: _offsetOpen ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: AnimatedScale(
                        scale: _offsetOpen ? 1 : 0.85,
                        alignment: Alignment.topRight,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: _OffsetPanel(playback: _playback),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _pluginActions() {
    final actions = <Widget>[];
    for (final plugin in widget.controller.installedPlugins) {
      if (!plugin.enabled) continue;
      for (final contribution in plugin.manifest.ui) {
        if (contribution.placement != 'playerAction') continue;
        actions.add(
          IconButton(
            tooltip: contribution.label.isEmpty
                ? plugin.name
                : contribution.label,
            icon: Icon(iconForName(contribution.icon)),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PluginDialogPage(
                  controller: widget.controller,
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
    return actions;
  }

  Future<void> _onMenu(String value) async {
    final song = _playback.currentSong;
    switch (value) {
      case 'queue':
        await showQueueSheet(context, _playback);
      case 'like':
        await _toggleLike();
      case 'share':
        if (song == null) return;
        try {
          final text = await widget.controller.shareSong(song);
          if (text.isEmpty) {
            _snack('该歌曲没有可分享的内容');
            return;
          }
          await Clipboard.setData(ClipboardData(text: text));
          _snack('分享内容已复制');
        } catch (e) {
          _snack('分享失败：$e');
        }
      case 'download':
        if (song == null) return;
        try {
          final ok =
              await widget.controller.downloadCurrent(song.provider);
          if (!ok) _snack('已取消下载');
        } catch (e) {
          _snack('下载失败：$e');
        }
      case 'offset-m':
        _playback.setLyricOffset(_playback.lyricOffsetMs - 500);
      case 'offset-p':
        _playback.setLyricOffset(_playback.lyricOffsetMs + 500);
      case 'offset-r':
        _playback.setLyricOffset(0);
      case 'sleep-15':
        _playback.setSleepTimer(const Duration(minutes: 15));
        _snack('将在 15 分钟后暂停');
      case 'sleep-30':
        _playback.setSleepTimer(const Duration(minutes: 30));
        _snack('将在 30 分钟后暂停');
      case 'sleep-60':
        _playback.setSleepTimer(const Duration(minutes: 60));
        _snack('将在 60 分钟后暂停');
      case 'sleep-off':
        _playback.setSleepTimer(null);
        _snack('已取消定时暂停');
    }
  }
}

/// QPlayer's AMLL cover motion: pause shrinks the artwork to 75% over 600 ms,
/// resume springs it back with a small overshoot over 500 ms.
class _PlaybackCover extends StatefulWidget {
  const _PlaybackCover({
    required this.song,
    required this.size,
    required this.radius,
    required this.playing,
    this.heroTag = 'now-playing-cover',
  });

  final Song song;
  final double size;
  final double radius;
  final bool playing;
  final Object? heroTag;

  @override
  State<_PlaybackCover> createState() => _PlaybackCoverState();
}

class _PlaybackCoverState extends State<_PlaybackCover>
    with SingleTickerProviderStateMixin {
  static const _pauseCurve = Cubic(0.4, 0.2, 0.1, 1.0);
  static const _resumeCurve = Cubic(0.3, 0.2, 0.2, 1.4);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
    value: 1,
  );
  late double _from = widget.playing ? 1 : 0.75;
  late double _to = _from;
  bool _resuming = true;

  double get _scale {
    final curve = _resuming ? _resumeCurve : _pauseCurve;
    return _from + (_to - _from) * curve.transform(_controller.value);
  }

  @override
  void didUpdateWidget(covariant _PlaybackCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    final current = _scale;
    _controller.stop();
    _from = current;
    _to = widget.playing ? 1.0 : 0.75;
    _resuming = widget.playing;
    _controller.duration = Duration(
      milliseconds: widget.playing ? 500 : 600,
    );
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: CoverArtFrame(
        url: widget.song.artworkUrl,
        size: widget.size,
        radius: widget.radius,
        icon: widget.song.isLocal
            ? Icons.audio_file_rounded
            : Icons.music_note_rounded,
      ),
    );
    final content = widget.heroTag == null
        ? cover
        : Hero(tag: widget.heroTag!, child: cover);
    return AnimatedBuilder(
      animation: _controller,
      child: content,
      builder: (context, child) =>
          Transform.scale(scale: _scale, child: child),
    );
  }
}

class _CoverModeOverlay extends StatelessWidget {
  const _CoverModeOverlay({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final AppController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final playback = controller.playback;
    final song = playback.currentSong;
    if (song == null) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _Backdrop(song: song),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = math.min(
                  constraints.maxWidth * 0.60,
                  constraints.maxHeight * 0.58,
                );
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PlaybackCover(
                      song: song,
                      size: size,
                      radius: size * 0.07,
                      playing: playback.playing,
                      heroTag: null,
                    ),
                    const SizedBox(height: 26),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (song.artistLabel.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                song.artistLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '轻点任意位置返回歌词',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OffsetPanel extends StatefulWidget {
  const _OffsetPanel({required this.playback});

  final PlaybackController playback;

  @override
  State<_OffsetPanel> createState() => _OffsetPanelState();
}

class _OffsetPanelState extends State<_OffsetPanel> {
  late double _value = widget.playback.lyricOffsetMs.toDouble().clamp(
        -5000,
        5000,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      elevation: 18,
      shadowColor: Colors.black87,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 320,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '歌词偏移',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_value.round()} ms',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Slider(
                min: -5000,
                max: 5000,
                divisions: 100,
                value: _value.clamp(-5000, 5000),
                onChanged: (value) => setState(() => _value = value),
                onChangeEnd: (value) =>
                    widget.playback.setLyricOffset(value.round()),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() => _value = 0);
                      widget.playback.setLyricOffset(0);
                    },
                    child: const Text('重置'),
                  ),
                  const Spacer(),
                  Text(
                    '正值：歌词提前',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.song});

  final Song? song;

  @override
  Widget build(BuildContext context) {
    final url = song?.artworkUrl.trim() ?? '';
    final ratio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final width = MediaQuery.sizeOf(context).width;
    final cacheWidth = (width * ratio).round().clamp(360, 2400);
    Widget image;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      image = Image.network(
        url,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.low,
      );
    } else if (url.isNotEmpty && File(url).existsSync()) {
      image = Image.file(
        File(url),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.low,
      );
    } else {
      image = const ColoredBox(color: Color(0xFF141726));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Color(0xAA000000),
            BlendMode.darken,
          ),
          child: image,
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xCC0A0B10),
                Color(0xF20A0B10),
                Color(0xFF0A0B10),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({
    required this.controller,
    required this.song,
    required this.liked,
    required this.onToggleLike,
    required this.onSnack,
  });

  final AppController controller;
  final Song song;
  final bool liked;
  final VoidCallback onToggleLike;
  final ValueChanged<String> onSnack;

  @override
  Widget build(BuildContext context) {
    final playback = controller.playback;
    final lyrics = controller.lyricSettings;
    return LayoutBuilder(
      builder: (context, constraints) {
        final coverSize = math.min(
          constraints.maxWidth - 88,
          math.min(330.0, constraints.maxHeight * 0.34),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
          child: Column(
            children: [
              const Spacer(flex: 1),
              _PlaybackCover(
                song: song,
                size: coverSize,
                radius: 28,
                playing: playback.playing,
              ),
              const SizedBox(height: 22),
              _TitleBlock(
                song: song,
                liked: liked,
                onToggleLike: onToggleLike,
                center: true,
              ),
              const SizedBox(height: 6),
              _ProgressBar(playback: playback),
              _Controls(playback: playback),
              _SecondaryActions(
                controller: controller,
                song: song,
                onSnack: onSnack,
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: LyricsView(
                    lyrics: playback.lyrics,
                    positionMs:
                        playback.positionMs + playback.lyricOffsetMs,
                    activeIndex: playback.lyricIndex,
                    onSeek: playback.seek,
                    playing: playback.playing,
                    fontSize: lyrics.fontSize,
                    fontWeight: lyrics.fontWeight,
                    lineSpacing: lyrics.lineSpacing,
                    alignment: lyrics.alignment,
                    showTranslation: lyrics.showTranslation,
                    showRomanization: lyrics.showRomanization,
                    shadow: lyrics.shadow,
                    fontFamily:
                        lyrics.fontFamily.isEmpty ? null : lyrics.fontFamily,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.controller,
    required this.song,
    required this.liked,
    required this.onToggleLike,
    required this.onSnack,
  });

  final AppController controller;
  final Song song;
  final bool liked;
  final VoidCallback onToggleLike;
  final ValueChanged<String> onSnack;

  @override
  Widget build(BuildContext context) {
    final playback = controller.playback;
    final lyrics = controller.lyricSettings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 8, 36, 24),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final coverSize = math.min(
                  constraints.maxWidth,
                  math.min(360.0, constraints.maxHeight * 0.40),
                );
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PlaybackCover(
                      song: song,
                      size: coverSize,
                      radius: coverSize * 0.09,
                      playing: playback.playing,
                    ),
                    SizedBox(height: coverSize < 320 ? 18 : 28),
                    _TitleBlock(
                      song: song,
                      liked: liked,
                      onToggleLike: onToggleLike,
                      center: true,
                    ),
                    const SizedBox(height: 8),
                    _ProgressBar(playback: playback),
                    _Controls(playback: playback),
                    _VolumeBar(playback: playback),
                    _SecondaryActions(
                      controller: controller,
                      song: song,
                      onSnack: onSnack,
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 36),
          Expanded(
            flex: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: LyricsView(
                lyrics: playback.lyrics,
                positionMs: playback.positionMs + playback.lyricOffsetMs,
                activeIndex: playback.lyricIndex,
                onSeek: playback.seek,
                playing: playback.playing,
                fontSize: lyrics.fontSize,
                fontWeight: lyrics.fontWeight,
                lineSpacing: lyrics.lineSpacing,
                alignment: lyrics.alignment,
                showTranslation: lyrics.showTranslation,
                showRomanization: lyrics.showRomanization,
                shadow: lyrics.shadow,
                fontFamily:
                    lyrics.fontFamily.isEmpty ? null : lyrics.fontFamily,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.song,
    required this.liked,
    required this.onToggleLike,
    this.center = false,
  });

  final Song song;
  final bool liked;
  final VoidCallback onToggleLike;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment:
          center ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment:
                center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: center ? TextAlign.center : TextAlign.left,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (song.artistLabel.isNotEmpty) song.artistLabel,
                  if (song.album?.name.isNotEmpty ?? false) song.album!.name,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: center ? TextAlign.center : TextAlign.left,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        IconButton(
          tooltip: liked ? '取消喜欢' : '喜欢',
          onPressed: onToggleLike,
          icon: Icon(
            liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: liked ? const Color(0xFFFF5C8A) : Colors.white70,
          ),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatefulWidget {
  const _ProgressBar({required this.playback});

  final PlaybackController playback;

  @override
  State<_ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<_ProgressBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = math.max(
      widget.playback.durationMs,
      widget.playback.currentSong?.durationMs ?? 0,
    );
    final max = math.max(duration, 1).toDouble();
    final value =
        (_dragValue ?? widget.playback.positionMs.toDouble()).clamp(0.0, max);
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
            thumbColor: Colors.white,
            overlayColor: Colors.white.withValues(alpha: 0.12),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value,
            max: max,
            onChanged: duration <= 0
                ? null
                : (next) => setState(() => _dragValue = next),
            onChangeEnd: duration <= 0
                ? null
                : (next) {
                    setState(() => _dragValue = null);
                    widget.playback.seek(next.round());
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _format((_dragValue ?? widget.playback.positionMs.toDouble())
                    .round()),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                _format(duration),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _format(int ms) {
    final total = (ms / 1000).floor().clamp(0, 359999);
    final minutes = total ~/ 60;
    final seconds = (total % 60).toString().padLeft(2, '0');
    if (total >= 3600) {
      final hours = total ~/ 3600;
      final rest = (total % 3600) ~/ 60;
      return '$hours:${rest.toString().padLeft(2, '0')}:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: playback.shuffle ? '关闭随机播放' : '随机播放',
          onPressed: () => playback.setShuffle(!playback.shuffle),
          icon: Icon(
            Icons.shuffle_rounded,
            color: playback.shuffle
                ? Theme.of(context).colorScheme.primary
                : Colors.white54,
          ),
        ),
        const SizedBox(width: 10),
        IconButton(
          tooltip: '上一首',
          iconSize: 34,
          onPressed: playback.hasPrevious ? playback.previous : null,
          icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 68,
          height: 68,
          child: FilledButton(
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            onPressed: playback.togglePlayPause,
            child: playback.resolving
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.black54,
                    ),
                  )
                : Icon(
                    playback.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 38,
                  ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: '下一首',
          iconSize: 34,
          onPressed: playback.hasNext ? playback.next : null,
          icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
        ),
        const SizedBox(width: 10),
        IconButton(
          tooltip: playback.repeatMode.label,
          onPressed: playback.cycleRepeatMode,
          icon: Icon(
            playback.repeatMode == RepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            color: playback.repeatMode == RepeatMode.off
                ? Colors.white54
                : Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _VolumeBar extends StatelessWidget {
  const _VolumeBar({required this.playback});

  final PlaybackController playback;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const Icon(
            Icons.volume_down_rounded,
            color: Colors.white54,
            size: 20,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                activeTrackColor: Colors.white70,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 5),
              ),
              child: Slider(
                value: playback.volume.clamp(0, 100),
                max: 100,
                onChanged: playback.setVolume,
              ),
            ),
          ),
          const Icon(
            Icons.volume_up_rounded,
            color: Colors.white54,
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _SecondaryActions extends StatelessWidget {
  const _SecondaryActions({
    required this.controller,
    required this.song,
    required this.onSnack,
  });

  final AppController controller;
  final Song song;
  final ValueChanged<String> onSnack;

  @override
  Widget build(BuildContext context) {
    final playback = controller.playback;
    final canShare = song.mediaId != null &&
        controller.supports(song.provider, ProviderCapability.share);
    final canDownload = song.provider != 'local';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: '播放队列',
          onPressed: () => showQueueSheet(context, playback),
          icon: const Icon(Icons.queue_music_rounded, color: Colors.white70),
        ),
        IconButton(
          tooltip: '歌词延迟 -0.5 秒',
          onPressed: () =>
              playback.setLyricOffset(playback.lyricOffsetMs - 500),
          icon: const Icon(Icons.remove_rounded, color: Colors.white54),
        ),
        Text(
          '${playback.lyricOffsetMs > 0 ? '+' : ''}'
          '${(playback.lyricOffsetMs / 1000).toStringAsFixed(1)}s',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        IconButton(
          tooltip: '歌词延迟 +0.5 秒',
          onPressed: () =>
              playback.setLyricOffset(playback.lyricOffsetMs + 500),
          icon: const Icon(Icons.add_rounded, color: Colors.white54),
        ),
        if (canShare)
          IconButton(
            tooltip: '分享',
            onPressed: () async {
              try {
                final text = await controller.shareSong(song);
                if (text.isEmpty) {
                  onSnack('该歌曲没有可分享的内容');
                  return;
                }
                await Clipboard.setData(ClipboardData(text: text));
                onSnack('分享内容已复制');
              } catch (e) {
                onSnack('分享失败：$e');
              }
            },
            icon: const Icon(Icons.ios_share_rounded, color: Colors.white70),
          ),
        if (canDownload)
          IconButton(
            tooltip: '下载',
            onPressed: () async {
              try {
                final ok = await controller.downloadCurrent(song.provider);
                if (!ok) onSnack('已取消下载');
              } catch (e) {
                onSnack('下载失败：$e');
              }
            },
            icon: const Icon(Icons.download_rounded, color: Colors.white70),
          ),
      ],
    );
  }
}
