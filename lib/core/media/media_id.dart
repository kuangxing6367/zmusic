import 'dart:convert';

import 'media_kind.dart';

/// Collision-free identity for media owned by a source plugin.
///
/// Wire form: `provider:kind:percent-encoded-native-id`
/// (same public contract the plugin ABI expects).
class MediaId {
  const MediaId(this.provider, this.kind, this.nativeId);

  static final RegExp _providerPattern =
      RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');
  static const int _maxNativeIdBytes = 2048;

  final String provider;
  final MediaKind kind;
  final String nativeId;

  factory MediaId.of(String provider, MediaKind kind, String nativeId) {
    if (!isValidProvider(provider)) {
      throw ArgumentError('invalid provider id: $provider');
    }
    if (nativeId.isEmpty) {
      throw ArgumentError('native id is empty');
    }
    if (utf8.encode(nativeId).length > _maxNativeIdBytes) {
      throw ArgumentError('native id is too long');
    }
    for (final unit in nativeId.codeUnits) {
      if (unit < 0x20 || unit == 0x7f) {
        throw ArgumentError('native id contains control characters');
      }
    }
    return MediaId(provider, kind, nativeId);
  }

  factory MediaId.parse(String value) {
    final first = value.indexOf(':');
    final second = first < 0 ? -1 : value.indexOf(':', first + 1);
    if (first <= 0 ||
        second <= first + 1 ||
        second == value.length - 1 ||
        value.indexOf(':', second + 1) >= 0) {
      throw ArgumentError('invalid media id: $value');
    }
    return MediaId.of(
      value.substring(0, first),
      MediaKind.fromWireName(value.substring(first + 1, second)),
      _decode(value.substring(second + 1)),
    );
  }

  static bool isValidProvider(String provider) =>
      _providerPattern.hasMatch(provider);

  /// Returns a new id with the native part replaced, keeping provider/kind.
  MediaId withNative(String newNativeId) =>
      MediaId.of(provider, kind, newNativeId);

  @override
  String toString() => '$provider:${kind.wireName}:${_encode(nativeId)}';

  @override
  bool operator ==(Object other) =>
      other is MediaId &&
      other.provider == provider &&
      other.kind == kind &&
      other.nativeId == nativeId;

  @override
  int get hashCode => Object.hash(provider, kind, nativeId);

  static String _encode(String value) {
    final bytes = utf8.encode(value);
    final out = StringBuffer();
    for (final raw in bytes) {
      final b = raw & 0xff;
      final unreserved = (b >= 0x61 && b <= 0x7a) ||
          (b >= 0x41 && b <= 0x5a) ||
          (b >= 0x30 && b <= 0x39) ||
          b == 0x2d ||
          b == 0x2e ||
          b == 0x5f ||
          b == 0x7e;
      if (unreserved) {
        out.writeCharCode(b);
      } else {
        out.write('%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}');
      }
    }
    return out.toString();
  }

  static String _decode(String value) {
    final bytes = <int>[];
    for (var i = 0; i < value.length;) {
      final c = value.codeUnitAt(i);
      if (c == 0x25) {
        if (i + 2 >= value.length) throw ArgumentError('truncated escape');
        final hi = int.tryParse(value.substring(i + 1, i + 2), radix: 16);
        final lo = int.tryParse(value.substring(i + 2, i + 3), radix: 16);
        if (hi == null || lo == null) throw ArgumentError('invalid escape');
        bytes.add((hi << 4) | lo);
        i += 3;
      } else {
        if (c > 0x7f) {
          throw ArgumentError('native id must be percent encoded');
        }
        bytes.add(c);
        i++;
      }
    }
    final decoded = utf8.decode(bytes);
    if (decoded.isEmpty) throw ArgumentError('native id is empty');
    return decoded;
  }
}
