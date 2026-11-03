enum MediaKind {
  song('song'),
  album('album'),
  artist('artist'),
  playlist('playlist'),
  user('user');

  const MediaKind(this.wireName);

  final String wireName;

  static MediaKind fromWireName(String value) {
    for (final kind in values) {
      if (kind.wireName == value) return kind;
    }
    throw ArgumentError('unknown media kind: $value');
  }
}
