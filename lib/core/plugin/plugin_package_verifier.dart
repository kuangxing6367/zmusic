import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/api.dart' show PublicKeyParameter;
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/prime256v1.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';

import 'plugin_compatibility.dart';
import 'plugin_hashes.dart';
import 'plugin_manifest.dart';

class VerifiedPluginPackage {
  VerifiedPluginPackage({
    required this.file,
    required this.manifest,
    required this.hashes,
    required this.signed,
    required this.packageDigest,
    required this.files,
  });

  final File file;
  final PluginManifest manifest;
  final Map<String, String> hashes;
  final bool signed;
  final String packageDigest;

  /// Raw verified entry bytes, keyed by package path.
  final Map<String, Uint8List> files;
}

class PluginPackageException implements Exception {
  PluginPackageException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Strict verifier for deterministic QPlayer `.qplug` archives.
class PluginPackageVerifier {
  static const String hashesPath = 'META-INF/qplayer-files.json';
  static const String signaturePath = 'META-INF/qplayer.sig';
  static const int maxFiles = 512;
  static const int maxEntryBytes = 16 * 1024 * 1024;
  static const int maxPackageBytes = 64 * 1024 * 1024;

  Future<VerifiedPluginPackage> verify(
    String path, {
    String? publisherKeyBase64,
    bool allowUnsigned = true,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw PluginPackageException('插件包不存在');
    }
    final archiveDigest = PluginHashes.hex(
      PluginHashes.sha256(await file.readAsBytes()),
    );

    final bytes = await file.readAsBytes();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw PluginPackageException('无法解压插件包: $e');
    }

    final entries = <String, ArchiveFile>{};
    var total = 0;
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final name = entry.name;
      _validatePath(name);
      if (entries.containsKey(name)) {
        throw PluginPackageException('重复的 zip 条目: $name');
      }
      entries[name] = entry;
      if (entries.length > maxFiles) {
        throw PluginPackageException('插件包含过多文件');
      }
      final size = entry.size;
      if (size < 0 || size > maxEntryBytes) {
        throw PluginPackageException('插件条目过大: $name');
      }
      total += size;
      if (total > maxPackageBytes) {
        throw PluginPackageException('插件包体积超过限制');
      }
    }

    Uint8List readRequired(String name, int limit) {
      final entry = entries[name];
      if (entry == null) throw PluginPackageException('缺少必需条目: $name');
      final content = entry.content;
      final data = content is Uint8List
          ? content
          : Uint8List.fromList((content as List).cast<int>());
      if (data.length > limit) {
        throw PluginPackageException('条目超过大小限制: $name');
      }
      return data;
    }

    final hashesBytes = readRequired(hashesPath, 2 * 1024 * 1024);
    final Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(utf8.decode(hashesBytes));
      if (value is! Map) throw const FormatException('not an object');
      decoded = value.cast<String, dynamic>();
    } catch (e) {
      throw PluginPackageException('哈希清单格式错误: $e');
    }
    final hashes = <String, String>{};
    for (final entry in decoded.entries) {
      hashes[entry.key] = entry.value?.toString() ?? '';
    }
    _validateHashes(hashes, entries);

    final signaturePresent = entries.containsKey(signaturePath);
    var trustedSignature = false;
    if (signaturePresent && publisherKeyBase64 != null) {
      final encoded = readRequired(signaturePath, 16 * 1024);
      final Uint8List signature;
      try {
        signature = base64Decode(utf8.decode(encoded).trim());
      } catch (_) {
        throw PluginPackageException('插件签名不是合法的 Base64');
      }
      if (!_verifyEcdsaP256(hashesBytes, signature, publisherKeyBase64)) {
        throw PluginPackageException('插件签名校验失败');
      }
      trustedSignature = true;
    } else if (!allowUnsigned) {
      throw PluginPackageException('插件包未签名');
    }

    final files = <String, Uint8List>{};
    for (final expected in hashes.entries) {
      final data = readRequired(expected.key, maxEntryBytes);
      final actual = PluginHashes.sha256Hex(data);
      if (actual != expected.value.toLowerCase()) {
        throw PluginPackageException('插件文件哈希不匹配: ${expected.key}');
      }
      files[expected.key] = data;
    }

    final manifestBytes = readRequired('plugin.json', maxEntryBytes);
    final PluginManifest manifest;
    try {
      final raw = jsonDecode(utf8.decode(manifestBytes));
      if (raw is! Map) throw const FormatException('manifest is not an object');
      manifest =
          PluginManifest.fromJson(raw.cast<String, dynamic>());
      manifest.validate();
      PluginCompatibility.requireCompatible(manifest);
    } on PluginPackageException {
      rethrow;
    } catch (e) {
      throw PluginPackageException('插件清单无效: $e');
    }
    if (!hashes.containsKey(manifest.entry)) {
      throw PluginPackageException('插件入口未被签名哈希覆盖');
    }
    for (final contribution in manifest.ui) {
      if (contribution.source.isNotEmpty &&
          !hashes.containsKey(contribution.source)) {
        throw PluginPackageException(
            '插件 UI 文件未被哈希覆盖: ${contribution.source}');
      }
    }

    return VerifiedPluginPackage(
      file: file,
      manifest: manifest,
      hashes: hashes,
      signed: trustedSignature,
      packageDigest: archiveDigest,
      files: files,
    );
  }

  static void _validateHashes(
      Map<String, String> hashes, Map<String, ArchiveFile> entries) {
    if (hashes.isEmpty) {
      throw PluginPackageException('插件哈希清单为空');
    }
    final expected = entries.keys.toSet()
      ..remove(hashesPath)
      ..remove(signaturePath);
    if (expected.length != hashes.length ||
        !expected.every(hashes.containsKey)) {
      throw PluginPackageException('哈希清单未精确覆盖插件文件');
    }
    if (!hashes.containsKey('plugin.json')) {
      throw PluginPackageException('缺少 plugin.json');
    }
    for (final entry in hashes.entries) {
      _validatePath(entry.key);
      if (!RegExp(r'^[A-Fa-f0-9]{64}$').hasMatch(entry.value)) {
        throw PluginPackageException('无效的 SHA-256: ${entry.key}');
      }
    }
  }

  static void _validatePath(String path) {
    try {
      PluginManifest.requirePackagePath('package', path, null);
    } on ArgumentError catch (e) {
      throw PluginPackageException(e.message.toString());
    }
  }

  static bool _verifyEcdsaP256(
    Uint8List message,
    Uint8List signature,
    String publicKeyBase64,
  ) {
    try {
      final der = base64Decode(publicKeyBase64);
      if (der.length < 65 || der[der.length - 65] != 0x04) return false;
      final pointBytes = der.sublist(der.length - 65);
      final curve = ECCurve_prime256v1();
      final point = curve.curve.decodePoint(pointBytes);
      if (point == null) return false;
      final publicKey = ECPublicKey(point, curve);
      final (r, s) = _parseDerSignature(signature);
      final signer = ECDSASigner(SHA256Digest());
      signer.init(false, PublicKeyParameter<ECPublicKey>(publicKey));
      return signer.verifySignature(message, ECSignature(r, s));
    } catch (_) {
      return false;
    }
  }

  static (BigInt, BigInt) _parseDerSignature(Uint8List signature) {
    var index = 0;
    if (signature[index++] != 0x30) {
      throw const FormatException('not a DER sequence');
    }
    final (_, seqLengthBytes) = _readDerLength(signature, index);
    index += seqLengthBytes;
    final values = <BigInt>[];
    while (index < signature.length && values.length < 2) {
      if (signature[index++] != 0x02) {
        throw const FormatException('not a DER integer');
      }
      final (length, lengthBytes) = _readDerLength(signature, index);
      index += lengthBytes;
      final value = signature.sublist(index, index + length);
      index += length;
      values.add(BigInt.parse(
        value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        radix: 16,
      ));
    }
    if (values.length != 2) throw const FormatException('bad signature');
    return (values[0], values[1]);
  }

  static (int, int) _readDerLength(Uint8List data, int offset) {
    final first = data[offset];
    if (first < 0x80) return (first, 1);
    final count = first & 0x7f;
    var value = 0;
    for (var i = 0; i < count; i++) {
      value = (value << 8) | data[offset + 1 + i];
    }
    return (value, 1 + count);
  }
}
