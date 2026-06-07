import 'dart:io';
import 'package:flutter/material.dart';
import 'package:freerasp/freerasp.dart';

class RaspManager {
  static Future<void> initialize() async {
    // Talsec configuration
    final config = TalsecConfig(
      androidConfig: AndroidConfig(
        packageName: 'com.example.x509_flutter',
        signingCertHashes: ['YOUR_SIGNING_CERT_HASH_HERE'],
        supportedStores: ['com.sec.android.app.samsungapps'],
      ),
      iosConfig: IOSConfig(
        bundleIds: ['com.example.x509Flutter'],
        teamId: 'SYNRC',
      ),
      watcherMail: 'ceo@zencrypted.uk',
      isProd: true,
    );

    // Callbacks for threats
    final callback = ThreatCallback(
      onAppIntegrity: () => _handleThreat('App Integrity compromised (Repackaging / reFlutter)'),
      onObfuscationIssues: () => _handleThreat('Obfuscation issues'),
      onDebug: () => _handleThreat('Debugging detected'),
      onDeviceBinding: () => _handleThreat('Device binding failed'),
      onDeviceID: () => _handleThreat('Device ID mismatch'),
      onHooks: () => _handleThreat('Hooking framework detected (Frida, Xposed)'),
      onPrivilegedAccess: () => _handleThreat('Jailbreak / Root detected'),
      onSecureHardwareNotAvailable: () => _handleThreat('Secure Hardware not available'),
      onSimulator: () => _handleThreat('Emulator detected')
    );

    // Start RASP
    Talsec.instance.attachListener(callback);
    await Talsec.instance.start(config);
  }

  static void _handleThreat(String threat) {
    debugPrint("🚨 RASP SECURITY ALERT: \$threat");
    // In production, this should clear sensitive memory, wipe keys, and exit gracefully
    exit(1);
  }
}
