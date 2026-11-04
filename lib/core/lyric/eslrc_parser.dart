import 'lrc_parser.dart';
import 'lyric_models.dart';

/// AMLL-style Enhanced LRC (`.eslrc`).
///
/// Every syllable is prefixed by its own `[mm:ss.xxx]`, and the line is
/// normally terminated by a final bare timestamp.
class EsLrcParser {
  EsLrcParser._();

  static final RegExp _ts = RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?]');

  static List<LyricLine> parse(String? content) {
    final out = <LyricLine>[];
    if (content == null) return out;

    for (final raw in content.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      final stamps = <int>[];
      final texts = <String>[];
      var lastTagEnd = 0;
      var seen = 0;
      for (final match in _ts.allMatches(line)) {
        if (seen > 0) {
          texts.add(line.substring(lastTagEnd, match.start));
        }
        stamps.add(_parseTime(match.group(1)!, match.group(2)!, match.group(3)));
        lastTagEnd = match.end;
        seen++;
      }
      // Tail text after the last tag (lenient; canonical AMLL ends bare).
      if (lastTagEnd < line.length) {
        texts.add(line.substring(lastTagEnd));
      }
      if (stamps.isEmpty) continue;

      final lyricLine = LyricLine();
      for (var i = 0; i < texts.length; i++) {
        final text = texts[i];
        if (text.isEmpty) continue;
        final start = stamps[i];
        final nextStart = i + 1 < stamps.length ? stamps[i + 1] : start + 500;
        lyricLine.syllables.add(LyricSyllable(
          text: text,
          startMs: start,
          durationMs: (nextStart - start).clamp(0, 1 << 30).toInt(),
        ));
      }
      if (lyricLine.syllables.isNotEmpty) out.add(lyricLine);
    }
    stableSortLyricLines(out);
    return out;
  }

  static int _parseTime(String minStr, String secStr, String? fracStr) {
    return int.parse(minStr) * 60000 +
        int.parse(secStr) * 1000 +
        LrcParser.fractionMs(fracStr);
  }
}
