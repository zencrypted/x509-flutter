import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Dart interface to the native Secure Enclave / Hardware Keystore channel.
class HardwareKeystore {
  static const _channel = MethodChannel('x509_multicast/keys');

  /// Requests the native layer to generate a non-exportable secp384r1 keypair.
  /// The key will be stored securely and protected by biometrics.
  static Future<bool> generateKey(String keyAlias) async {
    try {
      final result = await _channel.invokeMethod<bool>('generateKey', {'alias': keyAlias});
      return result ?? false;
    } on PlatformException {
      print("generateKey error: \${e.message}");
      return false;
    }
  }

  /// Requests the native layer to sign data using the hardware-backed key.
  /// This will trigger a biometric prompt (FaceID/TouchID) for the user.
  static Future<Uint8List?> signData(String keyAlias, Uint8List payload) async {
    try {
      final result = await _channel.invokeMethod<Uint8List>('signData', {
        'alias': keyAlias,
        'payload': payload,
      });
      return result;
    } on PlatformException {
      print("signData error: \${e.message}");
      return null;
    }
  }
}
