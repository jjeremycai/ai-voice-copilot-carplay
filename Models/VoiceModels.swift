//
//  VoiceModels.swift
//  Shaw
//

import Foundation

enum TTSProvider: String, Codable, CaseIterable {
    case cartesia
    case elevenlabs
    case openaiRealtime

    var displayName: String {
        switch self {
        case .cartesia: return "Cartesia"
        case .elevenlabs: return "ElevenLabs"
        case .openaiRealtime: return "OpenAI Realtime"
        }
    }
}

struct TTSVoice: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let provider: TTSProvider
    let requiresPro: Bool

    static let cartesiaVoices: [TTSVoice] = [
        TTSVoice(id: "cartesia/sonic-3:9626c31c-bec5-4cca-baa8-f8ba9e84c8bc", name: "Jacqueline", description: "Confident young American woman", provider: .cartesia, requiresPro: false),
        TTSVoice(id: "cartesia/sonic-3:a167e0f3-df7e-4d52-a9c3-f949145efdab", name: "Blake", description: "Energetic American man", provider: .cartesia, requiresPro: false),
        TTSVoice(id: "cartesia/sonic-3:f31cc6a7-c1e8-4764-980c-60a361443dd1", name: "Robyn", description: "Calm Australian woman", provider: .cartesia, requiresPro: false),
        TTSVoice(id: "cartesia/sonic-3:5c5ad5e7-1020-476b-8b91-fdcbe9cc313c", name: "Daniela", description: "Warm Mexican woman", provider: .cartesia, requiresPro: false)
    ]

    static let elevenlabsVoices: [TTSVoice] = [
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:cgSgspJ2msm6clMCkdW9", name: "Jessica", description: "Playful American woman", provider: .elevenlabs, requiresPro: false),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:iP95p4xoKVk53GoZ742B", name: "Chris", description: "Natural American man", provider: .elevenlabs, requiresPro: false),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:Xb7hH8MSUJpSbSDYk0k2", name: "Alice", description: "Friendly British woman", provider: .elevenlabs, requiresPro: false),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:cjVigY5qzO86Huf0OWal", name: "Eric", description: "Smooth Mexican man", provider: .elevenlabs, requiresPro: false)
    ]

    static let openaiRealtimeVoices: [TTSVoice] = [
        TTSVoice(id: "alloy", name: "Alloy", description: "Neutral balanced voice", provider: .openaiRealtime, requiresPro: true),
        TTSVoice(id: "echo", name: "Echo", description: "Warm friendly voice", provider: .openaiRealtime, requiresPro: true),
        TTSVoice(id: "fable", name: "Fable", description: "Expressive storytelling voice", provider: .openaiRealtime, requiresPro: true),
        TTSVoice(id: "onyx", name: "Onyx", description: "Deep authoritative voice", provider: .openaiRealtime, requiresPro: true),
        TTSVoice(id: "nova", name: "Nova", description: "Clear energetic voice", provider: .openaiRealtime, requiresPro: true),
        TTSVoice(id: "shimmer", name: "Shimmer", description: "Soft soothing voice", provider: .openaiRealtime, requiresPro: true)
    ]

    static func voices(for provider: TTSProvider) -> [TTSVoice] {
        switch provider {
        case .cartesia: return cartesiaVoices
        case .elevenlabs: return elevenlabsVoices
        case .openaiRealtime: return openaiRealtimeVoices
        }
    }
    
    static let `default` = cartesiaVoices[0]

    var isRealtimeMode: Bool {
        return provider == .openaiRealtime
    }
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
        case .claudeSonnet45, .claudeHaiku45:
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
        case .gemini25Pro: return "Most capable Gemini - Best for reasoning"
        case .gemini25Flash: return "Fast multimodal Gemini"
        case .gemini25FlashLite: return "Ultra-fast Gemini"
        case .gemini20Flash: return "Gemini 2.0 - Fast and capable"
        case .gemini20FlashLite: return "Gemini 2.0 - Lightning fast"
        case .deepseekV3: return "DeepSeek V3 - Open source reasoning"
        case .gptOss120B: return "GPT OSS 120B - Open source"
        }
    }

    var requiresPro: Bool {
        switch self {
        case .claudeSonnet45, .gemini25Pro:
            return true
        default:
            return false
        }
    }

    static func models(for provider: AIModelProvider) -> [AIModel] {
        return allCases.filter { $0.provider == provider }
    }
}
