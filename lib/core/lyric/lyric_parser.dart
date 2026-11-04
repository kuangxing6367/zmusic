import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';

import '../media/models.dart';
import 'eslrc_parser.dart';
import 'lrc_parser.dart';
import 'lyric_models.dart';
import 'lys_parser.dart';
import 'qrc_parser.dart';
import 'ttml_parser.dart';
import 'word_time_lrc_parser.dart';
import 'yrc_parser.dart';

/// Format dispatcher for plugin-provided and local lyric files.
///
/// Picks a backend by declared format or file
/// extension, then merge translation / romanization sidecars onto the nearest
/// main line by start time.
class LyricParser {
  LyricParser._();

  /// Parses the source-neutral assets a plugin returns from `lyrics`.
  static Lyrics fromPluginAssets(LyricsPayload payload) {
    if (payload.assets.isEmpty) return Lyrics.empty;

    LyricAsset? original;
    LyricAsset? translation;
    LyricAsset? romanization;
    for (final asset in payload.assets) {
      if (asset.text.isEmpty) continue;
      final role = asset.role.toLowerCase();
      if ((role == 'translation' || role == 'translated') &&
          translation == null) {
        translation = asset;
      } else if ((role == 'romanization' || role == 'romaji') &&
          romanization == null) {
        romanization = asset;
      } else {
        original ??= asset;
      }
    }
    if (original == null) return Lyrics.empty;

    final lines = parseContent(original.format, original.text).lines.toList();
    if (lines.isEmpty) return Lyrics(format: original.format);

    if (translation != null) {
      _attachParsedSidecar(
        lines,
        parseContent(translation.format, translation.text).lines.toList(),
        translation: true,
      );
    }
    if (romanization != null) {
      _attachParsedSidecar(
        lines,
        parseContent(romanization.format, romanization.text).lines.toList(),
        translation: false,
      );
    }
    return Lyrics(lines: lines, format: original.format);
  }

  static Lyrics parseContent(String format, String content) {
    final lower = format.trim().toLowerCase();
    final lines = switch (lower) {
      'ttml' => TtmlParser.parse(content),
      'qrc' => QrcParser.parse(content),
      'yrc' => YrcParser.parse(content),
      'eslrc' => EsLrcParser.parse(content),
      'lys' => LysParser.parse(content),
      'word-time-lrc' || 'wordtimelrc' =>
        WordTimeLrcParser.parse(content),
      _ => WordTimeLrcParser.looksLikeWordTimeLrc(content)
          ? WordTimeLrcParser.parse(content)
          : LrcParser.parse(content),
    };
    return Lyrics(lines: lines, format: lower);
  }

  /// Parses a lyric file with UTF-8 → GBK encoding fallback and extension
  /// dispatch (`.ttml`, `.lys`, `.qrc`, `.yrc`, `.eslrc`, otherwise LRC).
  static Future<Lyrics> parseFile(
    String path, {
    String? translationPath,
    String? romanizationPath,
  }) async {
    final content = await _readWithEncodingFallback(path);
    if (content == null) return Lyrics.empty;

    final lower = path.toLowerCase();
    final format = lower.endsWith('.ttml')
        ? 'ttml'
        : lower.endsWith('.lys')
            ? 'lys'
            : lower.endsWith('.qrc')
                ? 'qrc'
                : lower.endsWith('.yrc')
                    ? 'yrc'
                    : lower.endsWith('.eslrc')
                        ? 'eslrc'
                        : 'lrc';

    final lines = parseContent(format, content).lines.toList();
    if (lines.isEmpty) return Lyrics(format: format);

    if (translationPath != null) {
      final sidecar = await parseFile(translationPath);
      _attachParsedSidecar(lines, sidecar.lines.toList(), translation: true);
    }
    if (romanizationPath != null) {
      final sidecar = await parseFile(romanizationPath);
      _attachParsedSidecar(lines, sidecar.lines.toList(), translation: false);
    }
    return Lyrics(lines: lines, format: format);
  }

  static Future<String?> _readWithEncodingFallback(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      final decoded = !text.contains('\uFFFD')
          ? text
          : gbk.decode(bytes, allowMalformed: true);
      return decoded.startsWith('\uFEFF')
          ? decoded.substring(1)
          : decoded;
    } catch (_) {
      return null;
    }
  }

  /// Merges sidecar lines into [mainLines] by nearest start timestamp.
  static void _attachParsedSidecar(
    List<LyricLine> mainLines,
    List<LyricLine> sidecar, {
    required bool translation,
  }) {
    if (mainLines.isEmpty || sidecar.isEmpty) return;
    var j = 0;
    for (final line in sidecar) {
      final start = line.startMs;
      while (j + 1 < mainLines.length &&
          (mainLines[j + 1].startMs - start).abs() <
              (mainLines[j].startMs - start).abs()) {
        j++;
      }
      if (translation) {
        mainLines[j].translation = line.text;
      } else {
        mainLines[j].romanization = line.text;
      }
    }
  }
}
