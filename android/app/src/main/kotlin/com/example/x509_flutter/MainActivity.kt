package com.example.x509_flutter

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.spec.ECGenParameterSpec

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "x509_multicast/keys"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "generateKey" -> {
                    val alias = call.argument<String>("alias") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Alias required", null)
                    try {
                        val success = generateHardwareKey(alias)
                        result.success(success)
                    } catch (e: Exception) {
                        result.error("KEY_GEN_FAILED", e.localizedMessage, null)
                    }
                }
                "signData" -> {
                    val alias = call.argument<String>("alias") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Alias required", null)
                    val payload = call.argument<ByteArray>("payload") ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Payload required", null)
                    try {
                        val signature = signData(alias, payload)
                        result.success(signature)
                    } catch (e: Exception) {
                        result.error("SIGN_FAILED", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun generateHardwareKey(alias: String): Boolean {
        val keyPairGenerator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore"
        )
        
        val parameterSpec = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
        ).run {
            setAlgorithmParameterSpec(ECGenParameterSpec("secp384r1"))
            setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA384)
            setUserAuthenticationRequired(true) // Requires biometrics/device unlock
            // setInvalidatedByBiometricEnrollment(true) // Optional strict biometric binding
            build()
        }
        
        keyPairGenerator.initialize(parameterSpec)
        keyPairGenerator.generateKeyPair()
        return true
    }

    private fun signData(alias: String, payload: ByteArray): ByteArray {
        val keyStore = KeyStore.getInstance("AndroidKeyStore")
        keyStore.load(null)
        val privateKey = keyStore.getKey(alias, null) as java.security.PrivateKey
        
        val signature = Signature.getInstance("SHA384withECDSA")
        signature.initSign(privateKey)
        signature.update(payload)
        
        // Note: For setUserAuthenticationRequired(true), you normally need to wrap this in 
        // BiometricPrompt using the CryptoObject. This serves as the architectural skeleton.
        return signature.sign()
    }
}
