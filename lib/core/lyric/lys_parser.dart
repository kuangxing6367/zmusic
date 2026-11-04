import 'lyric_models.dart';

/// Lyricify Syllable (`.lys`) parser.
///
/// Each line: `[propertyN]text(startMs,durationMs)text(startMs,durationMs)…`
/// The leading `[N]` selects the vocal channel.
class LysParser {
  LysParser._();

  static final RegExp _property = RegExp(r'^\[(\d+)]');
  static final RegExp _syllable = RegExp(r'([^()]*?)\((\d+),(\d+)\)');

  static List<LyricLine> parse(String? content) {
    final out = <LyricLine>[];
    if (content == null) return out;

    for (final raw in content.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      var channel = LyricVocalChannel.main;
      var from = 0;
      final property = _property.firstMatch(line);
      if (property != null) {
        channel = LyricVocalChannel.fromProperty(int.parse(property.group(1)!));
        from = property.end;
      }

      final lyricLine = LyricLine(channel: channel);
      for (final match in _syllable.allMatches(line, from)) {
        lyricLine.syllables.add(LyricSyllable(
          text: match.group(1) ?? '',
          startMs: int.parse(match.group(2)!),
          durationMs: int.parse(match.group(3)!),
        ));
      }
      if (lyricLine.syllables.isNotEmpty) out.add(lyricLine);
    }
    stableSortLyricLines(out);
    return out;
  }
}
