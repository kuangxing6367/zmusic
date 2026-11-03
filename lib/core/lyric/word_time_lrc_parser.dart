import 'lyric_models.dart';

/// Per-word timestamped LRC used by some custom-API backends (QQ lyrics from
/// `go-music-api`): `朝[00:42.31]花[00:42.51]岁[00:42.79]`.
///
/// Ported from QPlayer's `WordTimeLrcParser`.
class WordTimeLrcParser {
  WordTimeLrcParser._();

  static final RegExp _token = RegExp(r'(.*?)\[(\d+):(\d+(?:\.\d+)?)]');

  /// True when a bracket timestamp is preceded by non-empty text, which never
  /// happens in plain line-level LRC.
  static bool looksLikeWordTimeLrc(String? content) {
    if (content == null) return false;
    for (final match in _token.allMatches(content)) {
      if ((match.group(1) ?? '').isNotEmpty) return true;
    }
    return false;
  }

  static List<LyricLine> parse(String? content) {
    final out = <LyricLine>[];
    if (content == null) return out;

    for (final raw in content.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      final texts = <String>[];
      final times = <int>[];
      for (final match in _token.allMatches(line)) {
        texts.add(match.group(1) ?? '');
        final minutes = int.parse(match.group(2)!);
        final seconds = double.parse(match.group(3)!);
        times.add(minutes * 60000 + (seconds * 1000).round());
      }

      // texts[i] is sung from times[i-1] to times[i]; texts[0] is the empty
      // run before the first bracket and carries no syllable.
      final lyricLine = LyricLine();
      for (var i = 1; i < texts.length; i++) {
        final text = texts[i];
        if (text.isEmpty) continue;
        final start = times[i - 1];
        lyricLine.syllables.add(LyricSyllable(
          text: text,
          startMs: start,
          durationMs: (times[i] - start).clamp(0, 1 << 30).toInt(),
        ));
      }
      if (lyricLine.syllables.isNotEmpty) out.add(lyricLine);
    }
    stableSortLyricLines(out);
    return out;
  }
}
