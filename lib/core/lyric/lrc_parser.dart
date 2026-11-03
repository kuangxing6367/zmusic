import 'lyric_models.dart';

/// LRC parser with Enhanced-LRC ("A2 extension") support, ported from
/// QPlayer's `LrcParser`. Plain lines are `[mm:ss.xx]text`; inline
/// `<mm:ss.xx>` tags split the body into karaoke syllables.
class LrcParser {
  LrcParser._();

  static final RegExp _lineTs =
      RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\]');
  static final RegExp _inlineTs =
      RegExp(r'<(\d+):(\d+)(?:[.:](\d+))?>');

  static List<LyricLine> parse(String? content) {
    final out = <LyricLine>[];
    if (content == null) return out;
    for (final raw in content.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      final stamps = <int>[];
      var lastEnd = 0;
      for (final match in _lineTs.allMatches(line)) {
        // Stop at metadata or stray leading text: timestamps must form a
        // contiguous prefix.
        if (match.start != lastEnd) break;
        stamps.add(_parseTime(
          match.group(1)!,
          match.group(2)!,
          match.group(3),
        ));
        lastEnd = match.end;
      }
      if (stamps.isEmpty) continue;

      final body = line.substring(lastEnd);
      for (final start in stamps) {
        final lyricLine = LyricLine();
        if (body.contains('<')) {
          _parseEnhancedBody(lyricLine, body, start);
        } else {
          lyricLine.syllables.add(
            LyricSyllable(text: body, startMs: start, durationMs: 0),
          );
        }
        out.add(lyricLine);
      }
    }

    stableSortLyricLines(out);
    // Untimed syllables inherit the gap to the next line, clamped so a long
    // outro does not keep one line active indefinitely.
    for (var i = 0; i < out.length; i++) {
      final line = out[i];
      final start = line.startMs;
      final next = i + 1 < out.length ? out[i + 1].startMs : start + 5000;
      final gap = (next - start).clamp(500, 8000).toInt();
      for (var j = 0; j < line.syllables.length; j++) {
        final syllable = line.syllables[j];
        if (syllable.durationMs == 0) {
          line.syllables[j] = LyricSyllable(
            text: syllable.text,
            startMs: syllable.startMs,
            durationMs: gap,
          );
        }
      }
    }
    return out;
  }

  static void _parseEnhancedBody(
    LyricLine out,
    String body,
    int lineStart,
  ) {
    final matches = _inlineTs.allMatches(body).toList();
    var cursorMs = lineStart;
    var cursorIdx = 0;
    var opened = false;
    String? pendingText;

    for (final match in matches) {
      final segment = body.substring(cursorIdx, match.start);
      final tagMs = _parseTime(
        match.group(1)!,
        match.group(2)!,
        match.group(3),
      );

      if (opened && pendingText != null) {
        out.syllables.add(LyricSyllable(
          text: pendingText,
          startMs: cursorMs,
          durationMs: (tagMs - cursorMs).clamp(0, 1 << 30).toInt(),
        ));
      } else if (!opened && segment.isNotEmpty) {
        out.syllables.add(LyricSyllable(
          text: segment,
          startMs: cursorMs,
          durationMs: (tagMs - cursorMs).clamp(0, 1 << 30).toInt(),
        ));
      }

      cursorMs = tagMs;
      cursorIdx = match.end;
      pendingText = null;
      opened = true;

      final nextTag = body.indexOf('<', cursorIdx);
      final run = nextTag < 0
          ? body.substring(cursorIdx)
          : body.substring(cursorIdx, nextTag);
      if (run.isNotEmpty) pendingText = run;
    }

    if (opened && pendingText != null) {
      // Last syllable has no closing tag — leave duration 0 so the post-pass
      // fills it from the next line's gap.
      out.syllables.add(LyricSyllable(
        text: pendingText,
        startMs: cursorMs,
        durationMs: 0,
      ));
    }
    if (out.syllables.isEmpty) {
      out.syllables.add(LyricSyllable(
        text: body.replaceAll(RegExp('<[^>]*>'), ''),
        startMs: lineStart,
        durationMs: 0,
      ));
    }
  }

  static int _parseTime(String minStr, String secStr, String? fracStr) {
    try {
      final minutes = int.parse(minStr);
      final seconds = int.parse(secStr);
      return minutes * 60000 + seconds * 1000 + fractionMs(fracStr);
    } on FormatException {
      return 0;
    }
  }

  /// Sub-second digits as milliseconds: "5" is 500ms, "05" is 50ms,
  /// "005" is 5ms. Longer runs truncate to milliseconds.
  static int fractionMs(String? fracStr) {
    if (fracStr == null || fracStr.isEmpty) return 0;
    final digits =
        fracStr.length >= 3 ? fracStr.substring(0, 3) : '${fracStr}000'.substring(0, 3);
    return int.tryParse(digits) ?? 0;
  }
}
