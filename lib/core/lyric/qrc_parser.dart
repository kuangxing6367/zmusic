import 'lyric_models.dart';

/// QQ Music QRC parser.
///
/// Each line: `[lineStartMs,lineDurationMs]text(startMs,dur)text(startMs,dur)…`
class QrcParser {
  QrcParser._();

  static final RegExp _lineHeader = RegExp(r'^\[(\d+),(\d+)]');
  static final RegExp _syllable = RegExp(r'([^()]*?)\((\d+),(\d+)\)');

  static List<LyricLine> parse(String? content) {
    final out = <LyricLine>[];
    if (content == null) return out;

    for (final raw in content.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      // Skip metadata header blocks that do not start with [digits,digits].
      final header = _lineHeader.firstMatch(line);
      if (header == null) continue;

      final lyricLine = LyricLine();
      for (final match in _syllable.allMatches(line, header.end)) {
        var text = match.group(1) ?? '';
        final start = int.parse(match.group(2)!);
        final duration = int.parse(match.group(3)!);

        // Word separators are encoded as " (0,0)" tuples. Anchor them at the
        // previous syllable's end so karaoke fill is not collapsed.
        if (start == 0 && duration == 0 && lyricLine.syllables.isNotEmpty) {
          final previous = lyricLine.syllables.last;
          lyricLine.syllables.add(
            LyricSyllable(
              text: text,
              startMs: previous.endMs,
              durationMs: 0,
            ),
          );
          continue;
        }
        lyricLine.syllables.add(
          LyricSyllable(text: text, startMs: start, durationMs: duration),
        );
      }
      if (lyricLine.syllables.isNotEmpty) out.add(lyricLine);
    }
    stableSortLyricLines(out);
    return out;
  }
}
