import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/export.dart' as pc;

class EncryptionService {
  Future<Uint8List> _deriveKey(String password, Uint8List salt) async {
    await Future.delayed(Duration.zero);
    final pbkdf2 = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(salt, 100000, 32));
    return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
  }

  Uint8List generateSalt() {
    final secureRandom = pc.FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(pc.KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom.nextBytes(16);
  }

  Future<String> encryptText(
    String plainText,
    String password,
    Uint8List salt,
  ) async {
    final derivedKey = await _deriveKey(password, salt);
    final key = encrypt.Key(derivedKey);
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return "${iv.base64}:${encrypted.base64}";
  }

  Future<String?> decryptText(
    String combined,
    String password,
    Uint8List salt,
  ) async {
    try {
      final parts = combined.split(':');
      if (parts.length != 2) return null;

      final iv = encrypt.IV.fromBase64(parts[0]);
      final encrypted = encrypt.Encrypted.fromBase64(parts[1]);
      final derivedKey = await _deriveKey(password, salt);
      final key = encrypt.Key(derivedKey);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      print("Error de desencriptación: $e");
      return null;
    }
  }
}
