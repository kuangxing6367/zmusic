import 'package:xml/xml.dart';

import 'lyric_models.dart';

/// AMLL-flavoured TTML parser, ported from QPlayer's `TtmlParser`.
///
/// Each `<p>` is one line and its `<span>` children are syllables. Vocal
/// channels come from `ttm:agent` declarations; inline `x-translation`,
/// `x-roman` and `x-bg` spans are handled like the Java host.
class TtmlParser {
  TtmlParser._();

  static List<LyricLine> parse(String? content) {
    final out = <LyricLine>[];
    if (content == null) return out;
    try {
      final document = XmlDocument.parse(content);
      final agents = _readAgents(document);
      final romajiByLineKey = _readTransliterations(document);

      final paragraphs = document.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'p');

      for (final paragraph in paragraphs) {
        final channel = agents[_attr(paragraph, 'ttm:agent', 'agent')] ??
            LyricVocalChannel.main;
        final lyricLine = LyricLine(channel: channel);

        final lineKey =
            _attr(paragraph, 'itunes:key', 'key') ?? _attr(paragraph, 'key', 'key');
        if (lineKey != null) {
          final romaji = romajiByLineKey[lineKey];
          if (romaji != null && romaji.isNotEmpty) {
            lyricLine.romanization = romaji;
          }
        }

        final lineStart = _parseClock(_attr(paragraph, 'begin', 'begin'));
        final lineEnd = _parseClock(_attr(paragraph, 'end', 'end'));
        final backgroundLines = <LyricLine>[];

        for (final child in paragraph.children) {
          if (child is XmlElement && child.name.local.toLowerCase() == 'span') {
            final role = (_attr(child, 'ttm:role', 'role') ?? '').toLowerCase();
            if (role.startsWith('x-translation')) {
              final text = child.innerText.trim();
              if (text.isNotEmpty) lyricLine.translation = text;
              continue;
            }
            if (role.startsWith('x-roman')) {
              final text = child.innerText.trim();
              if (text.isNotEmpty) lyricLine.romanization = text;
              continue;
            }
            if (role == 'x-bg') {
              final background = _parseInlineBgSpan(child, channel);
              if (background != null) backgroundLines.add(background);
              continue;
            }
            final start = _parseClock(_attr(child, 'begin', 'begin'));
            final end = _parseClock(_attr(child, 'end', 'end'));
            lyricLine.syllables.add(LyricSyllable(
              text: child.innerText,
              startMs: start,
              durationMs: (end - start).clamp(0, 1 << 30).toInt(),
            ));
          } else if (child is XmlText) {
            final text = child.value;
            if (text.isEmpty) continue;
            if (text.trim().isEmpty) {
              _appendSpaceToLast(lyricLine.syllables);
            } else {
              final cursor = lyricLine.syllables.isEmpty
                  ? lineStart
                  : lyricLine.syllables.last.endMs;
              lyricLine.syllables.add(LyricSyllable(
                text: text,
                startMs: cursor,
                durationMs: 0,
              ));
            }
          }
        }

        if (lyricLine.syllables.isEmpty) {
          final text = paragraph.innerText;
          if (text.trim().isNotEmpty) {
            lyricLine.syllables.add(LyricSyllable(
              text: text,
              startMs: lineStart,
              durationMs: (lineEnd - lineStart).clamp(0, 1 << 30).toInt(),
            ));
          }
        }
        if (lyricLine.syllables.isNotEmpty) out.add(lyricLine);
        // Background lines follow their main line so grouping stays adjacent.
        out.addAll(backgroundLines);
      }
    } catch (_) {
      // Malformed TTML produces no lyrics, matching the Java host's leniency.
    }
    return out;
  }

  static LyricLine? _parseInlineBgSpan(
    XmlElement span,
    LyricVocalChannel parentChannel,
  ) {
    final channel = parentChannel == LyricVocalChannel.duetRight
        ? LyricVocalChannel.backgroundRight
        : parentChannel == LyricVocalChannel.duetLeft
            ? LyricVocalChannel.backgroundLeft
            : LyricVocalChannel.background;
    final background = LyricLine(channel: channel);

    for (final child in span.children) {
      if (child is XmlElement && child.name.local.toLowerCase() == 'span') {
        final role = (_attr(child, 'ttm:role', 'role') ?? '').toLowerCase();
        if (role.startsWith('x-translation')) {
          final text = child.innerText.trim();
          if (text.isNotEmpty) background.translation = text;
          continue;
        }
        if (role.startsWith('x-roman')) {
          final text = child.innerText.trim();
          if (text.isNotEmpty) background.romanization = text;
          continue;
        }
        final start = _parseClock(_attr(child, 'begin', 'begin'));
        final end = _parseClock(_attr(child, 'end', 'end'));
        background.syllables.add(LyricSyllable(
          text: child.innerText,
          startMs: start,
          durationMs: (end - start).clamp(0, 1 << 30).toInt(),
        ));
      } else if (child is XmlText) {
        final text = child.value;
        if (text.isEmpty) continue;
        if (text.trim().isEmpty) {
          _appendSpaceToLast(background.syllables);
        } else if (background.syllables.isNotEmpty) {
          background.syllables.add(LyricSyllable(
            text: text,
            startMs: background.syllables.last.endMs,
            durationMs: 0,
          ));
        }
      }
    }
    return background.syllables.isEmpty ? null : background;
  }

  /// Maps `ttm:agent` ids to channels. Single-agent files are solo; files with
  /// two or more agents are duets (first → left, second → right).
  static Map<String, LyricVocalChannel> _readAgents(XmlDocument document) {
    final ids = <String>[];
    for (final element in document.descendants.whereType<XmlElement>()) {
      final name = element.name.local.toLowerCase();
      if (name != 'agent') continue;
      final id = _attr(element, 'xml:id', 'id') ?? _attr(element, 'id', 'id');
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    final result = <String, LyricVocalChannel>{};
    if (ids.length <= 1) {
      for (final id in ids) {
        result[id] = LyricVocalChannel.main;
      }
    } else {
      for (var i = 0; i < ids.length; i++) {
        result[ids[i]] = i == 0
            ? LyricVocalChannel.duetLeft
            : i == 1
                ? LyricVocalChannel.duetRight
                : LyricVocalChannel.main;
      }
    }
    return result;
  }

  static Map<String, String> _readTransliterations(XmlDocument document) {
    final result = <String, String>{};
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'text') continue;
      final forKey = _attr(element, 'for', 'for');
      if (forKey == null) continue;
      final text = element.innerText.trim();
      if (text.isNotEmpty) result[forKey] = text;
    }
    return result;
  }

  static void _appendSpaceToLast(List<LyricSyllable> syllables) {
    if (syllables.isEmpty) return;
    final last = syllables.last;
    if (last.text.endsWith(' ')) return;
    syllables[syllables.length - 1] = LyricSyllable(
      text: '${last.text} ',
      startMs: last.startMs,
      durationMs: last.durationMs,
    );
  }

  static String? _attr(XmlElement element, String qualified, String local) {
    final direct = element.getAttribute(qualified);
    if (direct != null && direct.isNotEmpty) return direct;
    final any = element.getAttribute(local, namespace: '*');
    if (any != null && any.isNotEmpty) return any;
    return null;
  }

  /// TTML clock: `"12.345"`, `"1:23.456"` or `"0:01:23.456"`.
  static int _parseClock(String? value) {
    if (value == null || value.isEmpty) return 0;
    final parts = value.split(':');
    try {
      final secondsPart = double.parse(parts.last);
      var ms = (secondsPart * 1000).round();
      if (parts.length >= 2) {
        ms += int.parse(parts[parts.length - 2]) * 60000;
      }
      if (parts.length >= 3) {
        ms += int.parse(parts[parts.length - 3]) * 3600000;
      }
      return ms;
    } on FormatException {
      return 0;
    }
  }
}
