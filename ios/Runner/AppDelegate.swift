import Flutter
import UIKit

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
