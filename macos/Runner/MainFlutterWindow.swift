import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  var eventSink: FlutterEventSink?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    
    setupChannels(controller: flutterViewController)

    super.awakeFromNib()
  }
  
  private func setupChannels(controller: FlutterViewController) {
      let methodChannel = FlutterMethodChannel(name: "x509_multicast/methods", binaryMessenger: controller.engine.binaryMessenger)
      methodChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
          guard let self = self else { return }
          self.handleMethodCall(call, result: result)
      }
      
      let eventChannel = FlutterEventChannel(name: "x509_multicast/events", binaryMessenger: controller.engine.binaryMessenger)
      eventChannel.setStreamHandler(self)
      
      // Start streaming MulticastService packets
      Task {
          let stream = await MulticastService.shared.makeDataStream()
          for await (data, ip) in stream {
              if let wrapper = try? CHAT_CHATMessage(derEncoded: ArraySlice(data)) {
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
}

extension MainFlutterWindow: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
