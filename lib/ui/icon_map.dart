import 'package:flutter/material.dart';

/// Maps plugin-declared icon names (Material icon identifiers) to icons.
IconData iconForName(String name) {
  const icons = <String, IconData>{
    'tune': Icons.tune_rounded,
    'settings': Icons.settings_rounded,
    'extension': Icons.extension_rounded,
    'download': Icons.download_rounded,
    'cloud': Icons.cloud_rounded,
    'cloud_download': Icons.cloud_download_rounded,
    'lyrics': Icons.lyrics_rounded,
    'group': Icons.group_rounded,
    'equalizer': Icons.equalizer_rounded,
    'wifi': Icons.wifi_rounded,
    'sync': Icons.sync_rounded,
    'playlist_play': Icons.playlist_play_rounded,
    'favorite': Icons.favorite_rounded,
    'share': Icons.ios_share_rounded,
    'account': Icons.account_circle_rounded,
    'person': Icons.person_rounded,
    'search': Icons.search_rounded,
    'music_note': Icons.music_note_rounded,
    'queue_music': Icons.queue_music_rounded,
    'album': Icons.album_rounded,
    'radio': Icons.radio_rounded,
    'lock': Icons.lock_rounded,
    'key': Icons.key_rounded,
    'delete': Icons.delete_rounded,
    'delete_sweep': Icons.delete_sweep_rounded,
    'history': Icons.history_rounded,
    'info': Icons.info_rounded,
    'help': Icons.help_rounded,
    'update': Icons.update_rounded,
    'upload': Icons.upload_rounded,
    'public': Icons.public_rounded,
    'language': Icons.language_rounded,
    'star': Icons.star_rounded,
    'add': Icons.add_rounded,
    'refresh': Icons.refresh_rounded,
  };
  return icons[name] ?? Icons.extension_rounded;
}
