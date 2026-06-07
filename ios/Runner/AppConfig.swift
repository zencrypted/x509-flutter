//
//  AppConfig.swift
//  ChatX509
//
//  Created by Chat509.
//

import SwiftUI
import Combine

/// Centralized configuration for the application using UserDefaults for persistence.
/// This allows "Tweaking" values at runtime via the Debug menu.
class AppConfig: ObservableObject {
    static let shared = AppConfig()
    
    enum AppMode: String, CaseIterable, Identifiable {
        case v1 = "v1 (P2P)"
        case v2 = "v2 (CA)"
        var id: String { self.rawValue }
    }
    
    @Published var appMode: AppMode {
        didSet { UserDefaults.standard.set(appMode.rawValue, forKey: "config_app_mode") }
    }

    
    // MARK: - Networking
    
    @Published var multicastPort: Int {
        didSet { UserDefaults.standard.set(multicastPort, forKey: "config_multicast_port") }
    }
    
    @Published var discoveryGroup: String {
        didSet { UserDefaults.standard.set(discoveryGroup, forKey: "config_discovery_group") }
    }
    
    @Published var chatGroup: String {
        didSet { UserDefaults.standard.set(chatGroup, forKey: "config_chat_group") }
    }
    
    // MARK: - Discovery Timing
    
    @Published var beaconInterval: Double {
        didSet { UserDefaults.standard.set(beaconInterval, forKey: "config_beacon_interval") }
    }
    
    @Published var presenceTimeout: Double {
        didSet { UserDefaults.standard.set(presenceTimeout, forKey: "config_presence_timeout") }
    }
    
    // MARK: - Identity
    
    @Published var identityGenerationTimeout: Double {
        didSet { UserDefaults.standard.set(identityGenerationTimeout, forKey: "config_identity_gen_timeout") }
    }
    
    @Published var ephemeralIdentityValidity: Double {
        didSet { UserDefaults.standard.set(ephemeralIdentityValidity, forKey: "config_ephemeral_validity") }
    }
    
    // MARK: - Debug
    
    @Published var showConsoleOnShake: Bool {
        didSet { UserDefaults.standard.set(showConsoleOnShake, forKey: "config_show_console") }
    }
    
    private init() {
        // Load with defaults
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "config_multicast_port": 55555,
            "config_discovery_group": "239.1.42.1",
            "config_chat_group": "239.1.42.28",
            "config_beacon_interval": 1.0,
            "config_presence_timeout": 60.0,
            "config_identity_gen_timeout": 30.0,
            "config_ephemeral_validity": 1800.0,
            "config_show_console": true
        ])
        if let savedMode = defaults.string(forKey: "config_app_mode"), let mode = AppMode(rawValue: savedMode) {
            self.appMode = mode
        } else {
            self.appMode = .v1
        }
        
        self.multicastPort = defaults.integer(forKey: "config_multicast_port")
        self.discoveryGroup = defaults.string(forKey: "config_discovery_group") ?? "239.1.42.1"
        self.chatGroup = defaults.string(forKey: "config_chat_group") ?? "239.1.42.28"
        self.beaconInterval = defaults.double(forKey: "config_beacon_interval")
        self.presenceTimeout = defaults.double(forKey: "config_presence_timeout")
        self.identityGenerationTimeout = defaults.double(forKey: "config_identity_gen_timeout")
        self.ephemeralIdentityValidity = defaults.double(forKey: "config_ephemeral_validity")
        self.showConsoleOnShake = defaults.bool(forKey: "config_show_console")
    }
    
    /// Reset all configurations to default
    func resetToDefaults() {
        appMode = .v1
        multicastPort = 55555
        discoveryGroup = "239.1.42.1"
        chatGroup = "239.1.42.28"
        beaconInterval = 1.0
        presenceTimeout = 60.0
        identityGenerationTimeout = 30.0
        ephemeralIdentityValidity = 1800.0
        showConsoleOnShake = true
    }
}
