import 'dart:ffi';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

/// Payload pushed from the main engine through desktop_multi_window.
class DesktopLyricPayload {
  const DesktopLyricPayload({
    this.line = '',
    this.translation = '',
    this.next = '',
    this.title = '',
    this.artist = '',
    this.playing = false,
    this.fontSize = 34,
    this.fontFamily = '',
    this.backgroundOpacity = 0.62,
  });

  final String line;
  final String translation;
  final String next;
  final String title;
  final String artist;
  final bool playing;
  final double fontSize;
  final String fontFamily;
  final double backgroundOpacity;

  factory DesktopLyricPayload.fromMap(Map<dynamic, dynamic> map) {
    String text(Object? value) => value?.toString() ?? '';
    return DesktopLyricPayload(
      line: text(map['line']),
      translation: text(map['translation']),
      next: text(map['next']),
      title: text(map['title']),
      artist: text(map['artist']),
      playing: map['playing'] == true,
      fontSize: (map['fontSize'] as num?)?.toDouble() ?? 34,
      fontFamily: text(map['fontFamily']),
      backgroundOpacity:
          (map['backgroundOpacity'] as num?)?.toDouble() ?? 0.62,
    );
  }
}

final ValueNotifier<DesktopLyricPayload> _payload =
    ValueNotifier(const DesktopLyricPayload());

/// Entry point for the secondary engine created by [DesktopLyricService].
///
/// desktop_multi_window creates a plain `WS_OVERLAPPEDWINDOW` and only
/// registers its own plugin in the new engine, so window_manager is not
/// available there. We style the window directly through Win32 instead:
/// frameless, always-on-top, hidden from taskbar/Alt-Tab, click-through and
/// uniformly translucent.
Future<void> runDesktopLyricWindow(String arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  _configureOverlayWindow();

  DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
    if (call.method == 'lyric' && call.arguments is Map) {
      _payload.value =
          DesktopLyricPayload.fromMap(call.arguments as Map<dynamic, dynamic>);
    }
    return null;
  });

  runApp(const _DesktopLyricApp());
}

void _configureOverlayWindow() {
  final className = 'FlutterMultiWindow'.toNativeUtf16();
  final hwnd = FindWindow(className, nullptr);
  free(className);
  if (hwnd == 0) {
    debugPrint('[desktop-lyric] overlay window not found');
    return;
  }

  // The second engine is the stability boundary we validate first; native
  // styling is reintroduced step by step once this window survives.
  final style = GetWindowLongPtr(hwnd, GWL_STYLE);
  SetWindowLongPtr(
    hwnd,
    GWL_STYLE,
    style &
        ~WS_CAPTION &
        ~WS_THICKFRAME &
        ~WS_SYSMENU &
        ~WS_MINIMIZEBOX &
        ~WS_MAXIMIZEBOX,
  );
  final exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  SetWindowLongPtr(
    hwnd,
    GWL_EXSTYLE,
    exStyle |
        WS_EX_LAYERED |
        WS_EX_TOOLWINDOW |
        WS_EX_TOPMOST |
        WS_EX_NOACTIVATE |
        WS_EX_TRANSPARENT,
  );
  SetLayeredWindowAttributes(hwnd, 0, 238, LWA_ALPHA);
}

class _DesktopLyricApp extends StatelessWidget {
  const _DesktopLyricApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.transparent,
        fontFamily: 'Microsoft YaHei UI',
      ),
      home: const _LyricSurface(),
    );
  }
}

class _LyricSurface extends StatelessWidget {
  const _LyricSurface();

  static const _shadows = <Shadow>[
    Shadow(blurRadius: 14, color: Color(0xCC000000), offset: Offset(0, 2)),
    Shadow(blurRadius: 26, color: Color(0x99000000)),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ValueListenableBuilder<DesktopLyricPayload>(
        valueListenable: _payload,
        builder: (context, payload, _) {
          final line = payload.line.trim();
          final hasLine = line.isNotEmpty;
          final family =
              payload.fontFamily.isEmpty ? null : payload.fontFamily;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF101218)
                  .withValues(alpha: payload.backgroundOpacity),
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              border: payload.backgroundOpacity > 0.01
                  ? Border.all(color: const Color(0x1FFFFFFF))
                  : null,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
                child: hasLine
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontFamily: family,
                              fontSize: payload.fontSize,
                              height: 1.18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                              shadows: _shadows,
                            ),
                          ),
                          if (payload.translation.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                payload.translation,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: const Color(0xE6FFFFFF),
                                  fontFamily: family,
                                  fontSize: payload.fontSize * 0.5,
                                  height: 1.25,
                                  fontWeight: FontWeight.w500,
                                  shadows: _shadows,
                                ),
                              ),
                            ),
                          if (payload.next.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                payload.next,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: const Color(0x99FFFFFF),
                                  fontFamily: family,
                                  fontSize: payload.fontSize * 0.42,
                                  height: 1.2,
                                  shadows: _shadows,
                                ),
                              ),
                            ),
                        ],
                      )
                    : Text(
                        [payload.title, payload.artist]
                            .where((part) => part.trim().isNotEmpty)
                            .join(' - '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xB3FFFFFF),
                          fontFamily: family,
                          fontSize: payload.fontSize * 0.47,
                          shadows: _shadows,
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}