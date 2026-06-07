//
//  MulticastService.swift
//  chat509
//
//  Created on 14.01.2026.
//

import Foundation
import Network

/// Handles UDP Multicast networking for the chat application (Network Looper)
actor MulticastService {
    static let shared = MulticastService()
    
    // MARK: - Configuration
    static var BROADCAST_GROUP: String { AppConfig.shared.discoveryGroup }
    static var CHAT_GROUP: String { AppConfig.shared.chatGroup }
    
    private var port: UInt16 { UInt16(AppConfig.shared.multicastPort) }
    private let bufferSize = 65536
    private let maxChunkSize = 1024
    
    // MARK: - State (Actor Isolated)
    
    private enum ServiceState {
        case stopped
        case starting
        case running
    }
    
    private var state: ServiceState = .stopped
    private var isRestarting = false
    private var receiveSocketFD: Int32 = -1
    private var sendSocketFD: Int32 = -1
    private var listeningTask: Task<Void, Never>?
    
    // Stats
    private var totalBytesSent = 0
    private var totalBytesReceived = 0
    private var selectedInterfaceIP: String? 
    
    // Debug Stats
    struct DebugStats: Sendable {
        let isRunning: Bool
        let totalBytesSent: Int
        let totalBytesReceived: Int
        // let pendingMessagesCount: Int // Removed
        let selectedInterfaceIP: String? 
    }
    
    func getDebugStats() -> DebugStats {
        let running: Bool
        if case .running = state { running = true } else { running = false }
        
        return DebugStats(
            isRunning: running,
            totalBytesSent: totalBytesSent,
            totalBytesReceived: totalBytesReceived,
            // pendingMessagesCount: 0,
            selectedInterfaceIP: selectedInterfaceIP
        )
    }

    private var continuations: [UUID: AsyncStream<(Data, String)>.Continuation] = [:]
    
    // Reassembly State
    private struct ReassemblyBuffer: Sendable {
        var chunks: [Int: Data]
        var totalChunks: Int
        var lastUpdate: Date
    }
    private var reassemblyBuffers: [Data: ReassemblyBuffer] = [:]
    
    // ...

    private func startListening() {
        let fd = receiveSocketFD
        guard fd >= 0 else { return }
        
        // Capture actor-isolated property before detached task
        let filterIP = self.selectedInterfaceIP
        
        listeningTask?.cancel()
        listeningTask = Task.detached { [weak self] in
            guard let self = self else { return }
            
            var buffer = [UInt8](repeating: 0, count: 65536)
            // var packetCounter = 0
            
            print("[Multicast] Receive Loop Started on FD \(fd)")
            
            while !Task.isCancelled {
                 var sender = sockaddr_storage()
                 var senderLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
                 
                 // Blocking Receive
                 let bytesRead = withUnsafeMutablePointer(to: &sender) { senderPtr in
                     senderPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebPtr in
                         recvfrom(fd, &buffer, buffer.count, 0, rebPtr, &senderLen)
                     }
                 }
                 
                if bytesRead > 0 {
                    let receivedData = Data(buffer[0..<bytesRead])
                    
                    // Extract IP
                    var ip = "Unknown"
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if withUnsafePointer(to: &sender, { senderPtr in
                        senderPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { rebPtr in
                            getnameinfo(rebPtr, senderLen, &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                        }
                    }) == 0 {
                        ip = String(cString: hostname)
                    }
                    
                    if ip != filterIP { // Filter own echo using captured value
                        await self.processReceivedPacket(receivedData, from: ip)
                    }
                } else if bytesRead < 0 {
                    let err = errno
                    if err == EBADF { break }
                    if err == EAGAIN || err == EWOULDBLOCK { continue }
                    
                    // On iOS, a socket might become invalid when backgrounded/resumed
                    print("[Multicast] Receive error: \(err). Loop continuing...")
                    try? await Task.sleep(nanoseconds: 500_000_000) // Back off on error
                }
                
                // Pacing
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
    }
    


    private func performMaintenance() {
        print("[Multicast] 💓 Heartbeat: \(continuations.count) listeners registered. TX: \(totalBytesSent), RX: \(totalBytesReceived)")
         if case .stopped = state { return }
         if case .starting = state { return }
         
         // Cleanup expired reassembly buffers (e.g. > 60s since last chunk)
         let now = Date()
         let expiredPrefixes = reassemblyBuffers.filter { now.timeIntervalSince($0.value.lastUpdate) > 60 }.map { $0.key }
         for prefix in expiredPrefixes {
             reassemblyBuffers.removeValue(forKey: prefix)
             print("[Multicast] ⚠️ Cleaned up expired reassembly buffer for \(prefix.map { String(format: "%02X", $0) }.joined().prefix(8))...")
         }
    }
    
    // Send Queue
    private var sendStreamContinuation: AsyncStream<SendRequest>.Continuation?
    
    // Made internal so other files don't see it (private), but Actor uses it.
    private struct SendRequest: Sendable {
        let data: Data
        let address: String
        let transactionId: UUID
        let chunks: Set<Int>? // If nil, send all
    }
    
    // MARK: - Initialization
    init() {
        // Initialize Send Queue Stream
        let (stream, continuation) = AsyncStream<SendRequest>.makeStream()
        self.sendStreamContinuation = continuation
        
        // Start Send Loop
        Task {
            await runSendLoop(stream: stream)
        }
    }

    // MARK: - Public API
    
    func start() async {
        if case .stopped = state {
            state = .starting
        } else {
            return
        }
        
        // Setup Socket
        // Run socket creation on detached task to avoid blocking actor if it takes time?
        // Socket creation is fast. `bind` is fast.
        let (rx, tx) = prepareSockets()
        
        // Check if we were stopped while preparing
        if case .starting = state {
            if rx >= 0 && tx >= 0 {
                state = .running
                receiveSocketFD = rx
                sendSocketFD = tx
                print("MulticastService started. Listening on \(MulticastService.BROADCAST_GROUP) and \(MulticastService.CHAT_GROUP). Port: \(port)")
                
                // Start Listening Task
                startListening() 
                
                startMaintenanceLoop()
                startNetworkMonitoring()
            } else {
                 print("MulticastService failed to start sockets.")
                 state = .stopped
                 if rx >= 0 { close(rx) }
                 if tx >= 0 { close(tx) }
            }
        } else {
            // State changed to stopped
            print("MulticastService start aborted (stopped concurrently).")
            if rx >= 0 { close(rx) }
            if tx >= 0 { close(tx) }
        }
    }
    
    func stop() async {
        state = .stopped
        
        if receiveSocketFD >= 0 {
            close(receiveSocketFD)
            receiveSocketFD = -1
        }
        
        listeningTask?.cancel()
        listeningTask = nil
        if sendSocketFD >= 0 {
            close(sendSocketFD)
            sendSocketFD = -1
        }
        
        monitor?.cancel()
        monitor = nil
        maintenanceTask?.cancel()
        
        // Finish and clear all listeners SAFELY
        let currentContinuations = continuations.values
        continuations.removeAll()
        for continuation in currentContinuations {
            continuation.finish()
        }
    }
    
    func send(data: Data, address: String = MulticastService.CHAT_GROUP, transactionId: UUID = UUID(), chunks: Set<Int>? = nil) {
        // Non-blocking yield
        sendStreamContinuation?.yield(SendRequest(data: data, address: address, transactionId: transactionId, chunks: chunks))
    }
    
    /// Returns a new stream for receiving data. Each caller gets their own stream.
    func makeDataStream() -> AsyncStream<(Data, String)> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(500)) { continuation in
            self.addContinuation(id: id, continuation: continuation)
            
            continuation.onTermination = { _ in
                Task { [weak self] in
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }
    
    // MARK: - Internal Logic
    
    private func addContinuation(id: UUID, continuation: AsyncStream<(Data, String)>.Continuation) {
        print("[Multicast] Adding listener \(id)")
        continuations[id] = continuation
    }
    
    private func removeContinuation(id: UUID) {
        print("[Multicast] Removing listener \(id)")
        continuations.removeValue(forKey: id)
    }
    
    private func runSendLoop(stream: AsyncStream<SendRequest>) async {
        for await request in stream {
             await processSendRequest(request)
        }
    }
    
    private func sendPacket(_ data: Data, address: String) {
        let fd = sendSocketFD
        
        guard fd >= 0 else { 
            print("[Multicast] ⚠️ Skipping send: Socket not initialized (FD: \(fd))")
            return 
        }
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(self.port).bigEndian
        inet_pton(AF_INET, address, &addr.sin_addr)
        
        let sent = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { reb in
                sendto(fd, [UInt8](data), data.count, 0, reb, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if sent > 0 {
            totalBytesSent += sent
        } else if sent < 0 {
            let err = errno
            print("[Multicast] ❌ Send failed: \(err) (\(address)). Size: \(data.count)")
            
            if err == ENETUNREACH || err == EHOSTUNREACH || err == ENETDOWN || err == EADDRNOTAVAIL {
                 print("[Multicast] CRITICAL network error detected in send. Path likely broken.")
            }
        }
    }
    
    // Async variant
    private func processSendRequest(_ request: SendRequest) async {
        let maxChunk = 1200 // 1.2KB - Fits reliably within 1500 byte MTU
        
        if request.data.count > maxChunk {
            let data = request.data
            let totalChunks = Int(ceil(Double(data.count) / Double(maxChunk)))
            
            let uuidBytes = withUnsafeBytes(of: request.transactionId.uuid) { Array($0) }
            let parentId = ASN1OctetString(contentBytes: ArraySlice(uuidBytes))
            
            print("[Multicast] Splitting \(data.count) bytes into \(totalChunks) chunks (Transaction: \(request.transactionId))")
            
            for i in 0..<totalChunks {
                // Support selective retransmission
                if let requested = request.chunks, !requested.contains(i) {
                    continue
                }
                
                let start = i * maxChunk
                let end = min(start + maxChunk, data.count)
                let chunkPayload = data[start..<end]
                
                // Wrap chunk in ASN.1 FileDesc
                var payloadSerializer = DER.Serializer()
                try? payloadSerializer.serialize(ASN1OctetString(contentBytes: ArraySlice(chunkPayload)))
                let payloadAny = try! ASN1Any(derEncoded: payloadSerializer.serializedBytes)
                
                let chunkFile = CHAT_FileDesc(
                    id: ASN1OctetString(contentBytes: ArraySlice(UUID().uuidString.utf8)),
                    mime: ASN1OctetString(contentBytes: ArraySlice("application/octet-stream".utf8)),
                    payload: payloadAny,
                    parentid: parentId,
                    data: [
                        CHAT_Feature(id: ASN1OctetString(contentBytes: []), key: ASN1OctetString(contentBytes: ArraySlice("chunk-index".utf8)), value: ASN1OctetString(contentBytes: ArraySlice("\(i)".utf8)), group: ASN1OctetString(contentBytes: [])),
                        CHAT_Feature(id: ASN1OctetString(contentBytes: []), key: ASN1OctetString(contentBytes: ArraySlice("chunk-total".utf8)), value: ASN1OctetString(contentBytes: ArraySlice("\(totalChunks)".utf8)), group: ASN1OctetString(contentBytes: []))
                    ]
                )
                
                let wrapped = CHAT_CHATMessage(
                    no: ArraySlice([0]),
                    uuid: ASN1OctetString(contentBytes: ArraySlice(withUnsafeBytes(of: UUID().uuid) { Array($0) })),
                    headers: [],
                    body: .file(chunkFile)
                )
                
                var serializer = DER.Serializer()
                if let _ = try? serializer.serialize(wrapped) {
                    sendPacket(Data(serializer.serializedBytes), address: request.address)
                }
                
                // Pace chunks
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }
        } else {
            sendPacket(request.data, address: request.address)
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
    }
    

    
    // MARK: - Monitoring State
    private var messageStatsEnabled = false
    
    func setMonitoringEnabled(_ enabled: Bool) {
        messageStatsEnabled = enabled
    }
    
    func processReceivedPacket(_ data: Data, from ip: String) {
        print("[Multicast] 📥 TRACE: Received \(data.count) bytes from \(ip)")
        
        // Decode wrapper
        guard let wrapper = try? CHAT_CHATMessage(derEncoded: ArraySlice(data)) else {
            publishData(data, from: ip)
            return
        }

        let proto = wrapper.body
        
        // MONITORING
        if messageStatsEnabled {
            var packetType = "Unknown"
            var topic = "0"
            var messageId = "Raw-\(UUID().uuidString.prefix(8))"
            var participantName = ip
            var destination: String? = nil
            
            // Extract UUID from wrapper for messageId
            let uuidBytes = Array(wrapper.uuid.bytes)
            if uuidBytes.count == 16 {
                let uuid = UUID(uuid: (uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3], uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
                                      uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11], uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]))
                messageId = uuid.uuidString
            }
            
            // Helper to extract serial and public key
            func extractCertInfo(_ raw: String) -> (name: String, serial: String, pubKey: String) {
                let parts = raw.split(separator: "|", maxSplits: 1)
                guard parts.count == 2,
                      let certData = Data(base64Encoded: String(parts[1])),
                      let cert = try? AuthenticationFramework_Certificate(derEncoded: ArraySlice(certData)) else {
                    return (raw, "", "")
                }
                let name = String(parts[0])
                let serialBytes = Data(cert.toBeSigned.serialNumber)
                let serial = serialBytes.prefix(4).map { String(format: "%02X", $0) }.joined()
                let pubKeyBytes = Data(cert.toBeSigned.subjectPublicKeyInfo.subjectPublicKey.bytes)
                let pubKey = pubKeyBytes.prefix(8).map { String(format: "%02X", $0) }.joined()
                return (name, serial, pubKey)
            }
            
            func formatWithCert(_ raw: String) -> String {
                let info = extractCertInfo(raw)
                if !info.serial.isEmpty {
                    return "\(info.name) [S:\(info.serial) K:\(info.pubKey)...]"
                }
                return raw
            }

            switch proto {
            case .message(let m):
                let isAck = m.type.rawValue == 4
                packetType = isAck ? "Ack" : "Message"
                topic = "1"
                let toRaw = String(decoding: m.to.bytes, as: UTF8.self)
                destination = toRaw == "broadcast" ? "Everyone" : formatWithCert(toRaw)
                let sender = String(decoding: m.from.bytes, as: UTF8.self)
                if !sender.isEmpty { participantName = formatWithCert(sender) }
            case .presence(let p):
                packetType = "Announcement"
                topic = "28"
                destination = "Everyone"
                let sender = String(decoding: p.nickname.bytes, as: UTF8.self)
                if !sender.isEmpty { participantName = formatWithCert(sender) }
            case .fileOffer(_): packetType = "FileOffer"; topic = "1"; destination = "Everyone"
            case .fileRequest(_): packetType = "FileRequest"; topic = "1"
            case .repairRequest(_): packetType = "FileRepair"; topic = "1"
            case .register(_): packetType = "Register"
            case .auth(let auth):
                packetType = "Auth"
                let nick = String(decoding: auth.nickname.bytes, as: UTF8.self)
                if !nick.isEmpty { participantName = formatWithCert(nick) }
            case .feature(_): packetType = "Feature"
            case .service(_): packetType = "Service"
            case .profile(_): packetType = "Profile"
            case .room(_): packetType = "Room"
            case .member(_): packetType = "Member"
            case .search(_): packetType = "Search"
            case .file(_): packetType = "File"
            case .typing(_): packetType = "Typing"
            case .friend(_): packetType = "Friend"
            case .history(_): packetType = "History"
            case .roster(_): packetType = "Roster"
            }
            
            // Task {
            //         packet: packetType,
            //         direction: "Received",
            //         bytes: data.count,
            //         ip: ip,
            //         messageId: messageId,
            //         topic: topic,
            //         participantName: participantName,
            //         to: destination
            //     )
            // }
        }
        
        // --- ASN.1 CHUNK REASSEMBLY ---
        if case .file(let fd) = proto, !fd.parentid.bytes.isEmpty {
            let parentData = Data(fd.parentid.bytes)
            var index: Int?
            var total: Int?
            
            for feature in fd.data {
                let key = String(decoding: feature.key.bytes, as: UTF8.self)
                let val = String(decoding: feature.value.bytes, as: UTF8.self)
                if key == "chunk-index" { index = Int(val) }
                else if key == "chunk-total" { total = Int(val) }
            }
            
            if let idx = index, let tot = total {
                var anySerializer = DER.Serializer()
                try? anySerializer.serialize(fd.payload)
                if let contentOctet = try? ASN1OctetString(derEncoded: anySerializer.serializedBytes) {
                    let chunkData = Data(contentOctet.bytes)
                    
                    if reassemblyBuffers[parentData] == nil {
                        reassemblyBuffers[parentData] = ReassemblyBuffer(chunks: [:], totalChunks: tot, lastUpdate: Date())
                    }
                    
                    reassemblyBuffers[parentData]?.chunks[idx] = chunkData
                    reassemblyBuffers[parentData]?.lastUpdate = Date()
                    
                    if reassemblyBuffers[parentData]?.chunks.count == tot {
                        var fullMessage = Data()
                        for i in 0..<tot {
                            if let c = reassemblyBuffers[parentData]?.chunks[i] {
                                fullMessage.append(c)
                            }
                        }
                        reassemblyBuffers.removeValue(forKey: parentData)
                        print("[Multicast] Reassembled \(tot) chunks (\(fullMessage.count) bytes)")
                        publishData(fullMessage, from: ip)
                    }
                }
                return // Do not publish individual chunk to listeners
            }
        }
        
        // Pass to listeners
        publishData(data, from: ip)
    }
    
    private func publishData(_ data: Data, from ip: String) {
        if continuations.isEmpty {
            print("[Multicast] ⚠️ Warning: Packet received but NO listeners registered.")
        } else {
             print("[Multicast] Yielding packet (\(data.count) bytes) to \(continuations.count) listeners.")
        }
        for (_, continuation) in continuations {
            continuation.yield((data, ip))
        }
    }
    
    // MARK: - Setup & Maintenance
    
    // Returns (receiveFD, sendFD)
    private func prepareSockets() -> (Int32, Int32) {
        // RX
        var rxFD: Int32 = -1
        let rfd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        if rfd >= 0 {
            var reuse: Int32 = 1
            setsockopt(rfd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(rfd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(rfd, SOL_SOCKET, SO_BROADCAST, &reuse, socklen_t(MemoryLayout<Int32>.size)) // Ensure RX can hear Broadcast
            
            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = in_addr_t(0) // INADDR_ANY (Explicit)
            
            print("[Multicast] Attempting to bind RX to INADDR_ANY:\(port)")
            
            let bindRes = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { reb in
                    bind(rfd, reb, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            
            if bindRes == 0 {
                 joinMulticastGroup(fd: rfd, address: MulticastService.BROADCAST_GROUP)
                 joinMulticastGroup(fd: rfd, address: MulticastService.CHAT_GROUP)
                 
                 // Set Receive Timeout to 1 second to allow cancellation checks
                 var tv = timeval(tv_sec: 1, tv_usec: 0)
                 setsockopt(rfd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                 
                 rxFD = rfd
            } else {
                 print("RX Bind Failed")
                 close(rfd)
            }
        }
        
        // TX
        var txFD: Int32 = -1
        let sfd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        if sfd >= 0 {
            var reuse: Int32 = 1
            setsockopt(sfd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(sfd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(sfd, SOL_SOCKET, SO_BROADCAST, &reuse, socklen_t(MemoryLayout<Int32>.size))
            
            // Defaults
            var ttl: UInt8 = 255
            setsockopt(sfd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))
            var loop: UInt8 = 1 // Enable Loopback for local testing (Emulator <-> Emulator)
            setsockopt(sfd, IPPROTO_IP, IP_MULTICAST_LOOP, &loop, socklen_t(MemoryLayout<UInt8>.size))
            
            configureOutgoingInterface(fd: sfd)
            txFD = sfd
        }
        
        return (rxFD, txFD)
    }
    
    private func joinMulticastGroup(fd: Int32, address: String) {
        // Skip broadcast addresses (255.255.255.255) as they don't require membership
        // joining them results in EINVAL (Error 22)
        if address == "255.255.255.255" || address.hasSuffix(".255") {
            print("MulticastService: Skipping multicast join for broadcast/unicast address: \(address)")
            return
        }
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            print("MulticastService: Failed to getifaddrs")
            return
        }
        defer { freeifaddrs(ifaddr) }
        
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            let name = String(cString: ptr.pointee.ifa_name)
            
            // Relaxed check: UP and NOT Loopback (consistent with configureOutgoingInterface)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK
            
            if addr.sa_family == UInt8(AF_INET) && isUp && !isLoopback {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    // Filter out virtual/vpn interfaces which often swallow multicast
                    if name.hasPrefix("utun") || name.hasPrefix("llw") || name.hasPrefix("awdl") {
                        continue
                    }
                    
                    let ip = String(cString: hostname)
                    
                    // Skip 127.x explicitly if not caught by loopback flag
                    if ip.hasPrefix("127.") { continue }
                    
                    var mreq = ip_mreq()
                    inet_pton(AF_INET, address, &mreq.imr_multiaddr)
                    inet_pton(AF_INET, ip, &mreq.imr_interface)
                    
                    let result = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, socklen_t(MemoryLayout<ip_mreq>.size))
                    if result == 0 {
                        print("MulticastService: SUCCESSFULLY Joined \(address) on interface \(name) (\(ip))")
                    } else {
                        print("MulticastService: FAILED to join \(address) on \(name) (\(ip)): \(errno)")
                    }
                }
            }
        }
    }
    

    
    // Helper to replace `joinMulticastGroup` to avoid copy-paste errors? 
    // It's lines 458-502. 
    // `configureOutgoingInterface` is lines 504-583.
    // `startMaintenanceLoop` lines 588-620.
    
    private func configureOutgoingInterface(fd: Int32) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            print("[Multicast] Failed to getifaddrs")
            return
        }
        defer { freeifaddrs(ifaddr) }
        
        var bestIP: String?
        var foundEn0 = false
        
        print("[Multicast] Scanning interfaces for outgoing config...")
        
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            let name = String(cString: ptr.pointee.ifa_name)
            
            // Basic Requirement: UP and NOT Loopback
            // (We removed strict RUNNING/MULTICAST check to be more permissive on iOS HW)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK
            
            if !isUp || isLoopback { continue }
            
            if addr.sa_family == UInt8(AF_INET) {
                // Use numeric-only conversion to avoid DNS blocks
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostname)
                    // Skip 127.x.x.x just in case
                    if ip.hasPrefix("127.") { continue }
                    
                    // Filter out virtual/vpn/bridge interfaces which often swallow multicast
                    if name.hasPrefix("utun") || name.hasPrefix("llw") || name.hasPrefix("awdl") || name.hasPrefix("bridge") || name.hasPrefix("tap") || name.hasPrefix("tun") {
                        continue
                    }
                    
                    print("[Multicast] Found candidate: \(name) - \(ip)")
                    
                    // Prioritize "en" (Ethernet/WiFi) interfaces
                    // This applies to both iOS and macOS to avoid VPN tunnels
                    if name.hasPrefix("en") {
                        bestIP = ip
                        foundEn0 = true // Treat any 'en' as a gold standard candidate
                        break 
                    }
                    
                    if !foundEn0 {
                        // Keep first valid interface found as candidate
                        if bestIP == nil { bestIP = ip }
                    }
                }
            }
        }
        
        if let ip = bestIP {
            var addr = in_addr()
            inet_pton(AF_INET, ip, &addr)
            let result = setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &addr, socklen_t(MemoryLayout<in_addr>.size))
            if result == 0 {
                print("[Multicast] Set outgoing multicast interface to: \(ip)")
                self.selectedInterfaceIP = ip
            } else {
                 print("[Multicast] Failed to set outgoing interface \(ip): \(errno)")
            }
        } else {
            // Explicitly default to system routing if scan failed
            print("[Multicast] WARNING: No suitable IPv4 multicast interface found! Using system defaults.")
            self.selectedInterfaceIP = "System Default (Scan Failed)"
        }
    }
    
    // MARK: - Maintenance (Cleanup Old Pending)
    private var maintenanceTask: Task<Void, Never>?
    
    private func startMaintenanceLoop() {
        maintenanceTask?.cancel()
        maintenanceTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                guard let self = self else { break }
                print("[Multicast] Maintenance tick")
                await self.performMaintenance()
            }
            print("[Multicast] Maintenance Task Cancelled")
        }
    }
    
    

    
    // MARK: - Network Monitoring
    private var monitor: NWPathMonitor?
    
    private func startNetworkMonitoring() {
        monitor?.cancel()
        let pathMonitor = NWPathMonitor()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                 Task { [weak self] in await self?.checkRestart(path: path) }
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        pathMonitor.start(queue: queue)
        monitor = pathMonitor
    }
    
    private func checkRestart(path: NWPath) {
        print("[Multicast] Network path updated: \(path.status). Interface: \(path.availableInterfaces.map { $0.name }.joined(separator: ", "))")
        
        if path.status == .satisfied {
            // Check if we were stopped or if the interface changed
            if state == .stopped {
                 print("[Multicast] Path became satisfied. Restarting transport...")
                 Task { await self.restart() }
            } else if state == .running {
                // Determine current best IP
                let currentIP = getBestInterfaceIP()
                if let newIP = currentIP, newIP != selectedInterfaceIP {
                    print("[Multicast] Interface IP changed (\(selectedInterfaceIP ?? "none") -> \(newIP)). Restarting transport...")
                    Task { await self.restart() }
                }
            }
        } else if path.status == .unsatisfied {
             print("[Multicast] Path unsatisfied. Transport may fail.")
        }
    }
    
    /// Helper to find best IP without modifying state
    private func getBestInterfaceIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        
        var candidate: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            let name = String(cString: ptr.pointee.ifa_name)
            if (flags & IFF_UP) == IFF_UP && (flags & IFF_LOOPBACK) == 0 && addr.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostname)
                    if ip.hasPrefix("127.") { continue }
                    if name.hasPrefix("utun") || name.hasPrefix("bridge") || name.hasPrefix("tap") { continue }
                    if name.hasPrefix("en") { return ip }
                    if candidate == nil { candidate = ip }
                }
            }
        }
        return candidate
    }
    
    func restart() async {
        guard !isRestarting else { 
            print("[Multicast] Restart already in progress. Skipping.")
            return 
        }
        isRestarting = true
        defer { isRestarting = false }
        
        await stop()
        try? await Task.sleep(nanoseconds: 500_000_000)
        await start()
        
        // await UserDiscoveryService.shared.restart()
    }
}
    

