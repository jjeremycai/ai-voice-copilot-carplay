//
//  UserSettings.swift
//  AI Voice Copilot
//

import Foundation

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

    @Published var toolCallingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(toolCallingEnabled, forKey: "toolCallingEnabled")
            // Skip dependency logic during initialization to preserve user preferences
            guard !isInitializing else { return }
            // Automatically disable web search when tool calling is disabled
            if !toolCallingEnabled {
                self.webSearchEnabled = false
            } else {
                // Automatically enable web search when tool calling is enabled
                self.webSearchEnabled = true
            }
        }
    }

    @Published var webSearchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(webSearchEnabled, forKey: "webSearchEnabled")
        }
    }

    static let shared = UserSettings()

    // Retention options: 0 = Never delete, > 0 = number of days
    
    // Flag to prevent didSet side effects during initialization
    private var isInitializing = true

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
            // Migrate from old defaults to new default (GPT-5 Nano)
            // This ensures users get the latest default even if they had an old default saved
            if model == .gpt5Mini || model == .gpt41Nano {
                self.selectedModel = .gpt5Nano
            } else {
                self.selectedModel = model
            }
        } else {
            self.selectedModel = .gpt5Nano
        }

        // Load selected voice (default to Cartesia Sonic 3)
        if let data = UserDefaults.standard.data(forKey: "selectedVoice"),
           let voice = try? JSONDecoder().decode(TTSVoice.self, from: data) {
            self.selectedVoice = voice
        } else {
            // Default to Cartesia Sonic 3 - Jacqueline
            self.selectedVoice = TTSVoice.default
        }

        // Load tool calling settings (default to enabled)
        // Load both values first, then set them in any order since didSet dependency logic
        // is skipped during initialization (via isInitializing flag)
        if UserDefaults.standard.object(forKey: "toolCallingEnabled") != nil {
            self.toolCallingEnabled = UserDefaults.standard.bool(forKey: "toolCallingEnabled")
        } else {
            self.toolCallingEnabled = true // Default to enabled
        }

        if UserDefaults.standard.object(forKey: "webSearchEnabled") != nil {
            self.webSearchEnabled = UserDefaults.standard.bool(forKey: "webSearchEnabled")
        } else {
            self.webSearchEnabled = true // Default to enabled
        }
        
        // Mark initialization as complete - dependency logic will now apply to future changes
        isInitializing = false
    }
}

