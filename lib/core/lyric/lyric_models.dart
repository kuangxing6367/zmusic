/// Vocal channel of a lyric line.
enum LyricVocalChannel {
  main,
  background,
  duetLeft,
  duetRight,
  backgroundLeft,
  backgroundRight;

  static LyricVocalChannel fromProperty(int n) {
    switch (n) {
      case 2:
        return LyricVocalChannel.background;
      case 3:
        return LyricVocalChannel.duetLeft;
      case 4:
        return LyricVocalChannel.duetRight;
      case 5:
        return LyricVocalChannel.backgroundLeft;
      case 6:
        return LyricVocalChannel.backgroundRight;
      default:
        return LyricVocalChannel.main;
    }
  }
}

class LyricSyllable {
  const LyricSyllable({
    required this.text,
    required this.startMs,
    required this.durationMs,
  });

  final String text;
  final int startMs;
  final int durationMs;

  int get endMs => startMs + durationMs;
}

/// One sung line; text is the concatenation of its syllables, matching
/// The syllable list is the source of truth for timing.
class LyricLine {
  LyricLine({
    List<LyricSyllable>? syllables,
    this.channel = LyricVocalChannel.main,
    this.translation = '',
    this.romanization = '',
  }) : syllables = syllables ?? <LyricSyllable>[];

  final List<LyricSyllable> syllables;
  final LyricVocalChannel channel;

  /// Sidecar lines for the same time range (empty when absent).
  String translation;
  String romanization;

  int get startMs => syllables.isEmpty ? 0 : syllables.first.startMs;

  int get endMs => syllables.isEmpty ? 0 : syllables.last.endMs;

  String get text => syllables.map((s) => s.text).join();

  bool get hasTranslation => translation.trim().isNotEmpty;

  bool get hasRomanization => romanization.trim().isNotEmpty;

  bool get isBackground =>
      channel == LyricVocalChannel.background ||
      channel == LyricVocalChannel.backgroundLeft ||
      channel == LyricVocalChannel.backgroundRight;

  bool get isDuetRight =>
      channel == LyricVocalChannel.duetRight ||
      channel == LyricVocalChannel.backgroundRight;

  /// Progress (0..1) of the currently sung syllable, used for karaoke fill.
  double wordProgress(int positionMs) {
    if (syllables.isEmpty) return 0;
    for (var i = 0; i < syllables.length; i++) {
      final syllable = syllables[i];
      if (positionMs < syllable.startMs) return 0;
      final end = syllable.startMs + syllable.durationMs;
      if (positionMs < end) {
        if (syllable.durationMs <= 0) return 1;
        return ((positionMs - syllable.startMs) / syllable.durationMs)
            .clamp(0.0, 1.0);
      }
    }
    return 1;
  }
}

/// A main line together with the background-vocal lines that belong to it,
/// exactly how the TTML/YRC parsers emit groups.
class LyricGroup {
  LyricGroup(this.line) : backgrounds = <LyricLine>[];

  final LyricLine line;
  final List<LyricLine> backgrounds;

  int get startMs => line.startMs;

  int get endMs {
    var end = line.endMs;
    for (final bg in backgrounds) {
      if (bg.endMs > end) end = bg.endMs;
    }
    return end;
  }

  bool get hasBackgrounds => backgrounds.isNotEmpty;
}

class Lyrics {
  Lyrics({List<LyricLine> lines = const [], this.format = ''})
      : lines = List.unmodifiable(lines);
  static final Lyrics empty = Lyrics();

  final List<LyricLine> lines;
  final String format;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  List<LyricGroup> get groups => _groups ??= _buildGroups();
  List<LyricGroup>? _groups;

  List<LyricGroup> _buildGroups() {
    final result = <LyricGroup>[];
    for (final line in lines) {
      if (line.isBackground && result.isNotEmpty) {
        result.last.backgrounds.add(line);
      } else {
        result.add(LyricGroup(line));
      }
    }
    return result;
  }

  /// Index into [groups] of the line active at [positionMs] (-1 before the
  /// first line).
  int indexAt(int positionMs) {
    final list = groups;
    if (list.isEmpty) return -1;
    var low = 0;
    var high = list.length - 1;
    var result = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (list[mid].startMs <= positionMs) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return result;
  }
}

/// Sorts by start time while preserving insertion order for equal timestamps
/// (Dart's `List.sort` is not stable, and main/background line adjacency
/// depends on it).
void stableSortLyricLines(List<LyricLine> lines) {
  final indexed = <(int, LyricLine)>[
    for (var i = 0; i < lines.length; i++) (i, lines[i]),
  ];
  indexed.sort((a, b) {
    final byTime = a.$2.startMs.compareTo(b.$2.startMs);
    return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < lines.length; i++) {
    lines[i] = indexed[i].$2;
  }
}
