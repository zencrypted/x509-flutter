import Flutter
import UIKit
import Foundation
import CryptoKit
import LocalAuthentication

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  var eventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
        let methodChannel = FlutterMethodChannel(name: "x509_multicast/methods", binaryMessenger: controller.binaryMessenger)
        methodChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            guard let self = self else { return }
            self.handleMethodCall(call, result: result)
        }
        
        let eventChannel = FlutterEventChannel(name: "x509_multicast/events", binaryMessenger: controller.binaryMessenger)
        eventChannel.setStreamHandler(self)
        
        let keysChannel = FlutterMethodChannel(name: "x509_multicast/keys", binaryMessenger: controller.binaryMessenger)
        keysChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
            switch call.method {
            case "generateKey":
                guard let args = call.arguments as? [String: Any], let alias = args["alias"] as? String else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Alias required", details: nil))
                    return
                }
                do {
                    let success = try HardwareKeyManager.shared.generateKey(alias: alias)
                    result(success)
                } catch {
                    result(FlutterError(code: "KEY_GEN_FAILED", message: error.localizedDescription, details: nil))
                }
            case "signData":
                guard let args = call.arguments as? [String: Any], 
                      let alias = args["alias"] as? String,
                      let payloadData = (args["payload"] as? FlutterStandardTypedData)?.data else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Alias and payload required", details: nil))
                    return
                }
                do {
                    let signature = try HardwareKeyManager.shared.signData(alias: alias, payload: payloadData)
                    result(FlutterStandardTypedData(bytes: signature))
                } catch {
                    result(FlutterError(code: "SIGN_FAILED", message: error.localizedDescription, details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        // Start streaming MulticastService packets
        Task {
            let stream = await MulticastService.shared.makeDataStream()
            for await (data, ip) in stream {
                // Try decoding wrapper locally or send raw back to flutter
                // We'll send raw and let dart decode, or send string encoded
                // Since user wants "ASN.1 DER serializer keep the same", we have the generated swift files!
                if let wrapper = try? CHAT_CHATMessage(derEncoded: ArraySlice(data)) {
                    // It's a CHATMessage, let's just send the fact we received it to Dart
                    let msg = "Received from \(ip) -> UUID: \(wrapper.uuid.bytes.map { String(format: "%02hhx", $0) }.joined())"
                    DispatchQueue.main.async {
                        self.eventSink?(msg)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.eventSink?("Received raw from \(ip): \(data.count) bytes")
                    }
                }
            }
        }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      switch call.method {
      case "start":
          Task {
              await MulticastService.shared.start()
              DispatchQueue.main.async { result(true) }
          }
      case "stop":
          Task {
              await MulticastService.shared.stop()
              DispatchQueue.main.async { result(true) }
          }
      case "sendPresence":
          // Send a dummy presence message
          Task {
              let p = CHAT_Presence(nickname: ASN1OctetString(contentBytes: ArraySlice("FlutterUser".utf8)), status: .online)
              let uuidBytes = withUnsafeBytes(of: UUID().uuid) { Array($0) }
              let wrapper = CHAT_CHATMessage(no: ArraySlice([0]), uuid: ASN1OctetString(contentBytes: ArraySlice(uuidBytes)), headers: [], body: .presence(p))
              var serializer = DER.Serializer()
              if let _ = try? serializer.serialize(wrapper) {
                  await MulticastService.shared.send(data: Data(serializer.serializedBytes))
                  DispatchQueue.main.async { result(true) }
              } else {
                  DispatchQueue.main.async { result(false) }
              }
          }
      case "sendEncryptedMessage":
          if let typedData = call.arguments as? FlutterStandardTypedData {
              let payloadData = typedData.data
              Task {
                  // Direct send over Multicast Service. Payload is already encrypted CMS (via FFI in Dart)
                  await MulticastService.shared.send(data: payloadData)
                  DispatchQueue.main.async { result(true) }
              }
          } else {
              result(FlutterError(code: "INVALID_ARGUMENT", message: "Expected a byte array", details: nil))
          }
      default:
          result(FlutterMethodNotImplemented)
      }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

extension AppDelegate: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}

class HardwareKeyManager {
    static let shared = HardwareKeyManager()
    private init() {}
    
    enum KeyError: Error {
        case generationFailed
        case signingFailed
        case keyNotFound
    }
    
    func generateKey(alias: String) throws -> Bool {
        let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            nil
        )!
        
        do {
            // Generate secp384r1 in Secure Enclave
            // Note: Secure Enclave explicitly supports P256. 
            // Cossacks recommends secp384r1. P384 is NOT supported in Secure Enclave directly, 
            // only P256 is. We will use P256 for Secure Enclave natively.
            // If strictly P384 is needed, it cannot be in Secure Enclave, only Keychain.
            // For the sake of the RASP/Enclave recommendation, we demonstrate the API usage:
            let privateKey = try SecureEnclave.P256.Signing.PrivateKey(
                compactRepresentable: false,
                accessControl: accessControl,
                authenticationContext: LAContext()
            )
            
            // Store the key data reference in keychain if needed, 
            // though CryptoKit manages Secure Enclave keys via generic password/keychain query implicitly 
            // when saving the data representation.
            let keyData = privateKey.dataRepresentation
            
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: alias,
                kSecValueData as String: keyData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            
            SecItemDelete(query as CFDictionary)
            let status = SecItemAdd(query as CFDictionary, nil)
            
            return status == errSecSuccess
        } catch {
            print("HardwareKeyManager: Failed to generate key - \(error)")
            throw KeyError.generationFailed
        }
    }
    
    func signData(alias: String, payload: Data) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: alias,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess, let keyData = item as? Data else {
            throw KeyError.keyNotFound
        }
        
        do {
            let privateKey = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: keyData)
            let signature = try privateKey.signature(for: payload)
            return signature.derRepresentation
        } catch {
            print("HardwareKeyManager: Failed to sign data - \(error)")
            throw KeyError.signingFailed
        }
    }
}
