import 'lyric_models.dart';

/// NetEase Cloud Music YRC parser.
///
/// Each line: `[lineStartMs,lineDurationMs](sylStart,sylDur,flag)text...`
/// Background vocals are inlined in full-width parentheses `（…）`; they are
/// split into a separate background line appended right after the main one.
class YrcParser {
  YrcParser._();

  static final RegExp _lineHeader = RegExp(r'^\[(\d+),(\d+)]');
  static final RegExp _syllable = RegExp(r'\((\d+),(\d+),(\d+)\)([^(]*)');

  static List<LyricLine> parse(String? content) {
    final out = <LyricLine>[];
    if (content == null) return out;

    for (final raw in content.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final header = _lineHeader.firstMatch(line);
      if (header == null) continue;

      final main = LyricLine();
      final background = LyricLine(channel: LyricVocalChannel.background);
      var inBackground = false;

      for (final match in _syllable.allMatches(line, header.end)) {
        final start = int.parse(match.group(1)!);
        final duration = int.parse(match.group(2)!);
        final text = match.group(4) ?? '';

        final hasOpen = text.contains('（');
        final hasClose = text.contains('）');
        // Brackets are markers, not lyric content.
        final stripped = text.replaceAll('（', '').replaceAll('）', '');
        final toBackground = inBackground || hasOpen;
        if (hasOpen) inBackground = true;
        if (stripped.isNotEmpty) {
          (toBackground ? background : main).syllables.add(
            LyricSyllable(
              text: stripped,
              startMs: start,
              durationMs: duration,
            ),
          );
        }
        if (hasClose) inBackground = false;
      }

      if (main.syllables.isNotEmpty) out.add(main);
      if (background.syllables.isNotEmpty) out.add(background);
    }
    stableSortLyricLines(out);
    return out;
  }
}
