import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;

class PluginHashes {
  PluginHashes._();

  static Uint8List sha256(List<int> bytes) =>
      Uint8List.fromList(c.sha256.convert(bytes).bytes);

  static String hex(List<int> bytes) {
    final out = StringBuffer();
    for (final b in bytes) {
      out.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return out.toString();
  }

  static String sha256Hex(List<int> bytes) => hex(sha256(bytes));

  static String textSha256Hex(String text) => hex(sha256(utf8.encode(text)));
}
