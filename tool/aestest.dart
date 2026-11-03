import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/ecb.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';
import 'package:pointycastle/paddings/pkcs7.dart';

void main() {
  const b64 =
      '+6CJ7usl0OXT5E0N3Avs5lqdT+JN68IhBAwnx0ogw1lAQj0tVum4/e3HnU7jOPrnSn1xbIBZYnSAOH9LFVKoFK5klogigXcVYKAFMep3gXpWBooe3pJYPr0x8UB10OWbBHaKK0FCGtLgqow4Mz+sty6vn/BhSO0Us/Sw3G+5g3MvtTI5pYhGRk6N2YXXGrR7uLa37GfarCqFjSE41mw5Dw==';
  final data = base64Decode(b64);
  final hex =
      'ab1d5a430f6bb04a3f01e81ddd72bd916d5ce591248ac128714806d7f8fb1b84';
  final key = Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16)
  ]);
  print('cipher bytes=${data.length} key=${key.length}');
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()));
  cipher.init(
    false,
    PaddedBlockCipherParameters<CipherParameters?, CipherParameters?>(
      KeyParameter(key),
      null,
    ),
  );
  try {
    final out = cipher.process(data);
    print('out=${out.length} text=${utf8.decode(out, allowMalformed: true)}');
  } catch (e) {
    print('decrypt failed: $e');
  }
}
