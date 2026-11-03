enum ProviderCapability {
  hotSearch('hotSearch'),
  searchSongs('searchSongs'),
  searchAlbums('searchAlbums'),
  searchArtists('searchArtists'),
  searchPlaylists('searchPlaylists'),
  songDetails('songDetails'),
  playlistDetails('playlistDetails'),
  artistDetails('artistDetails'),
  albumDetails('albumDetails'),
  home('home'),
  account('account'),
  userPlaylists('userPlaylists'),
  recent('recent'),
  resolveStream('resolveStream'),
  lyrics('lyrics'),
  scrobble('scrobble'),
  like('like'),
  playlistMutation('playlistMutation'),
  playlistCover('playlistCover'),
  playlistReorder('playlistReorder'),
  heartRecommendation('heartRecommendation'),
  share('share'),
  matchSong('matchSong'),
  login('login'),
  @Deprecated('manifest-only compatibility')
  listenTogether('listenTogether');

  const ProviderCapability(this.wireName);

  final String wireName;

  static ProviderCapability fromWireName(String value) {
    for (final capability in values) {
      if (capability.wireName == value) return capability;
    }
    throw ArgumentError('unknown provider capability: $value');
  }
}
