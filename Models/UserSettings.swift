//
//  UserSettings.swift
//  AI Voice Copilot
//

import Foundation

// Forward declarations for models defined in CallScreen
enum AIModel: String, Codable { case gpt4oMini = "gpt-4o-mini", gpt4o = "gpt-4o", gpt4Turbo = "gpt-4-turbo" }
enum TTSProvider: String, Codable { case cartesia, elevenlabs }
struct TTSVoice: Identifiable, Codable, Equatable { let id: String; let name: String; let description: String; let provider: TTSProvider }

class UserSettings: ObservableObject {
    @Published var loggingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(loggingEnabled, forKey: "loggingEnabled")
        }
    }

    @Published var retentionDays: Int {
        didSet {
            UserDefaults.standard.set(retentionDays, forKey: "retentionDays")
        }
    }

    @Published var hasSeenOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasSeenOnboarding, forKey: "hasSeenOnboarding")
        }
    }

    @Published var selectedModel: AIModel {
        didSet {
            if let data = try? JSONEncoder().encode(selectedModel) {
                UserDefaults.standard.set(data, forKey: "selectedModel")
            }
        }
    }

    @Published var selectedVoice: TTSVoice {
        didSet {
            if let data = try? JSONEncoder().encode(selectedVoice) {
                UserDefaults.standard.set(data, forKey: "selectedVoice")
            }
        }
    }

    static let shared = UserSettings()

    // Retention options: 0 = Never delete, > 0 = number of days

    private init() {
        self.loggingEnabled = UserDefaults.standard.bool(forKey: "loggingEnabled")

        // Check if retentionDays key exists to distinguish between "not set" (default to 30) and "set to 0" (never delete)
        if UserDefaults.standard.object(forKey: "retentionDays") != nil {
            self.retentionDays = UserDefaults.standard.integer(forKey: "retentionDays")
        } else {
            self.retentionDays = 30 // Default to 30 days if not set
        }

        self.hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")

        // Load selected model
        if let data = UserDefaults.standard.data(forKey: "selectedModel"),
           let model = try? JSONDecoder().decode(AIModel.self, from: data) {
            self.selectedModel = model
        } else {
            self.selectedModel = .gpt4oMini
        }

        // Load selected voice
        if let data = UserDefaults.standard.data(forKey: "selectedVoice"),
           let voice = try? JSONDecoder().decode(TTSVoice.self, from: data) {
            self.selectedVoice = voice
        } else {
            self.selectedVoice = TTSVoice(id: "cartesia-katie", name: "Katie", description: "Friendly female voice", provider: .cartesia)
        }
    }
}

