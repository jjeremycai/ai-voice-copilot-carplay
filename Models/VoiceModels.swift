//
//  VoiceModels.swift
//  Shaw
//

import Foundation

enum TTSProvider: String, Codable, CaseIterable {
    case cartesia
    case elevenlabs
    
    var displayName: String {
        switch self {
        case .cartesia: return "Cartesia"
        case .elevenlabs: return "ElevenLabs"
        }
    }
}

struct TTSVoice: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let provider: TTSProvider
    
    static let cartesiaVoices: [TTSVoice] = [
        TTSVoice(id: "cartesia-katie", name: "Katie", description: "Friendly female voice", provider: .cartesia),
        TTSVoice(id: "cartesia-kiefer", name: "Kiefer", description: "Professional male voice", provider: .cartesia),
        TTSVoice(id: "cartesia-kyle", name: "Kyle", description: "Casual male voice", provider: .cartesia),
        TTSVoice(id: "cartesia-tessa", name: "Tessa", description: "Warm female voice", provider: .cartesia)
    ]
    
    static let elevenlabsVoices: [TTSVoice] = [
        TTSVoice(id: "elevenlabs-rachel", name: "Rachel", description: "Clear female voice", provider: .elevenlabs),
        TTSVoice(id: "elevenlabs-clyde", name: "Clyde", description: "Deep male voice", provider: .elevenlabs),
        TTSVoice(id: "elevenlabs-roger", name: "Roger", description: "Mature male voice", provider: .elevenlabs),
        TTSVoice(id: "elevenlabs-sarah", name: "Sarah", description: "Young female voice", provider: .elevenlabs),
        TTSVoice(id: "elevenlabs-laura", name: "Laura", description: "Professional female voice", provider: .elevenlabs),
        TTSVoice(id: "elevenlabs-charlie", name: "Charlie", description: "Energetic male voice", provider: .elevenlabs)
    ]
    
    static func voices(for provider: TTSProvider) -> [TTSVoice] {
        switch provider {
        case .cartesia: return cartesiaVoices
        case .elevenlabs: return elevenlabsVoices
        }
    }
    
    static let `default` = cartesiaVoices[0]
}

enum AIModelProvider: String, Codable, CaseIterable {
    case openai
    case anthropic
    case google
    case other

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .google: return "Google"
        case .other: return "Other"
        }
    }
}

enum AIModel: String, Codable, CaseIterable {
    // OpenAI GPT-4.1 Series
    case gpt41 = "openai/gpt-4.1"
    case gpt41Mini = "openai/gpt-4.1-mini"
    case gpt41Nano = "openai/gpt-4.1-nano"

    // OpenAI GPT-5 Series
    case gpt5 = "openai/gpt-5"
    case gpt5Mini = "openai/gpt-5-mini"
    case gpt5Nano = "openai/gpt-5-nano"

    // OpenAI GPT-4o Series
    case gpt4o = "openai/gpt-4o"
    case gpt4oMini = "openai/gpt-4o-mini"

    // Anthropic Claude 4.5 Series
    case claudeSonnet45 = "claude-sonnet-4-5"
    case claudeHaiku45 = "claude-haiku-4-5"

    // Anthropic Claude Opus
    case claudeOpus41 = "claude-opus-4-1"

    // Google Gemini 2.5 Series
    case gemini25Pro = "google/gemini-2.5-pro"
    case gemini25Flash = "google/gemini-2.5-flash"
    case gemini25FlashLite = "google/gemini-2.5-flash-lite"

    // Google Gemini 2.0 Series
    case gemini20Flash = "google/gemini-2.0-flash"
    case gemini20FlashLite = "google/gemini-2.0-flash-lite"

    // Other Models
    case deepseekV3 = "deepseek-ai/deepseek-v3"
    case gptOss120B = "openai/gpt-oss-120b"

    var provider: AIModelProvider {
        switch self {
        case .gpt41, .gpt41Mini, .gpt41Nano,
             .gpt5, .gpt5Mini, .gpt5Nano,
             .gpt4o, .gpt4oMini, .gptOss120B:
            return .openai
        case .claudeSonnet45, .claudeHaiku45, .claudeOpus41:
            return .anthropic
        case .gemini25Pro, .gemini25Flash, .gemini25FlashLite,
             .gemini20Flash, .gemini20FlashLite:
            return .google
        case .deepseekV3:
            return .other
        }
    }

    var displayName: String {
        switch self {
        case .gpt41: return "GPT-4.1"
        case .gpt41Mini: return "GPT-4.1 Mini"
        case .gpt41Nano: return "GPT-4.1 Nano"
        case .gpt5: return "GPT-5"
        case .gpt5Mini: return "GPT-5 Mini"
        case .gpt5Nano: return "GPT-5 Nano"
        case .gpt4o: return "GPT-4o"
        case .gpt4oMini: return "GPT-4o Mini"
        case .claudeSonnet45: return "Claude Sonnet 4.5"
        case .claudeHaiku45: return "Claude Haiku 4.5"
        case .claudeOpus41: return "Claude Opus 4.1"
        case .gemini25Pro: return "Gemini 2.5 Pro"
        case .gemini25Flash: return "Gemini 2.5 Flash"
        case .gemini25FlashLite: return "Gemini 2.5 Flash Lite"
        case .gemini20Flash: return "Gemini 2.0 Flash"
        case .gemini20FlashLite: return "Gemini 2.0 Flash Lite"
        case .deepseekV3: return "DeepSeek V3"
        case .gptOss120B: return "GPT OSS 120B"
        }
    }

    var description: String {
        switch self {
        case .gpt41: return "Latest GPT-4.1 - Most capable reasoning"
        case .gpt41Mini: return "Balanced speed and capability"
        case .gpt41Nano: return "Ultra-fast, efficient for simple tasks"
        case .gpt5: return "GPT-5 - Next generation model"
        case .gpt5Mini: return "GPT-5 Mini - Fast and capable"
        case .gpt5Nano: return "GPT-5 Nano - Lightning fast"
        case .gpt4o: return "GPT-4o - Powerful multimodal model"
        case .gpt4oMini: return "GPT-4o Mini - Fast and efficient"
        case .claudeSonnet45: return "Most capable Claude - Best for complex tasks"
        case .claudeHaiku45: return "Fast Claude - Great for quick responses"
        case .claudeOpus41: return "Claude Opus - Advanced reasoning"
        case .gemini25Pro: return "Most capable Gemini - Best for reasoning"
        case .gemini25Flash: return "Fast multimodal Gemini"
        case .gemini25FlashLite: return "Ultra-fast Gemini"
        case .gemini20Flash: return "Gemini 2.0 - Fast and capable"
        case .gemini20FlashLite: return "Gemini 2.0 - Lightning fast"
        case .deepseekV3: return "DeepSeek V3 - Open source reasoning"
        case .gptOss120B: return "GPT OSS 120B - Open source"
        }
    }

    static func models(for provider: AIModelProvider) -> [AIModel] {
        return allCases.filter { $0.provider == provider }
    }
}
