//
//  VoicePreviewService.swift
//  AI Voice Copilot
//

import Foundation
import AVFoundation
import Combine

/// Service for generating and caching voice preview audio samples
@MainActor
class VoicePreviewService: NSObject, ObservableObject {
    static let shared = VoicePreviewService()
    
    private let previewText = "Hello, this is a preview of my voice. How do I sound?"
    private var audioPlayers: [String: AVAudioPlayer] = [:]
    private var previewCache: [String: URL] = [:]
    @Published var playingVoiceId: String?
    
    private override init() {
        super.init()
    }
    
    /// Generate or retrieve cached preview URL for a voice
    func getPreviewURL(for voice: TTSVoice) async throws -> URL {
        let cacheKey = voice.id
        
        // Check if already cached
        if let cachedURL = previewCache[cacheKey] {
            return cachedURL
        }
        
        // Generate preview via backend
        let url = try await generatePreview(voice: voice)
        previewCache[cacheKey] = url
        return url
    }
    
    /// Play preview for a voice
    func playPreview(for voice: TTSVoice) async throws {
        let cacheKey = voice.id
        
        // Stop any currently playing preview
        stopAllPreviews()
        
        // Get or generate preview URL
        let previewURL = try await getPreviewURL(for: voice)
        
        // Create and play audio player
        let player = try AVAudioPlayer(contentsOf: previewURL)
        player.delegate = self
        player.prepareToPlay()
        audioPlayers[cacheKey] = player
        playingVoiceId = cacheKey
        player.play()
    }
    
    /// Stop preview for a specific voice
    func stopPreview(for voice: TTSVoice) {
        let cacheKey = voice.id
        audioPlayers[cacheKey]?.stop()
        audioPlayers[cacheKey] = nil
        if playingVoiceId == cacheKey {
            playingVoiceId = nil
        }
    }
    
    /// Stop all playing previews
    func stopAllPreviews() {
        audioPlayers.values.forEach { $0.stop() }
        audioPlayers.removeAll()
        playingVoiceId = nil
    }
    
    /// Check if a preview is currently playing for a voice
    func isPlaying(for voice: TTSVoice) -> Bool {
        let cacheKey = voice.id
        return playingVoiceId == cacheKey && (audioPlayers[cacheKey]?.isPlaying ?? false)
    }
    
    /// Map voice ID to preview file name
    /// Maps the app's voice IDs to the backend preview file names
    private func getPreviewFileName(for voice: TTSVoice) -> String {
        // Map voice IDs to preview file names
        // This mapping is needed because the app's voice IDs don't match the backend preview file names
        
        switch voice.id {
        // Cartesia voices - map to available preview files
        case "cartesia/sonic-3:9626c31c-bec5-4cca-baa8-f8ba9e84c8bc": // Jacqueline
            return "cartesia-katie"
        case "cartesia/sonic-3:a167e0f3-df7e-4d52-a9c3-f949145efdab": // Blake
            return "cartesia-kiefer"
        case "cartesia/sonic-3:f31cc6a7-c1e8-4764-980c-60a361443dd1": // Robyn
            return "cartesia-tessa"
        case "cartesia/sonic-3:5c5ad5e7-1020-476b-8b91-fdcbe9cc313c": // Daniela
            return "cartesia-kyle"
            
        // ElevenLabs voices - map to available preview files
        case "elevenlabs/eleven_turbo_v2_5:cgSgspJ2msm6clMCkdW9": // Jessica
            return "elevenlabs-rachel"
        case "elevenlabs/eleven_turbo_v2_5:iP95p4xoKVk53GoZ742B": // Chris
            return "elevenlabs-clyde"
        case "elevenlabs/eleven_turbo_v2_5:Xb7hH8MSUJpSbSDYk0k2": // Alice
            return "elevenlabs-laura"
        case "elevenlabs/eleven_turbo_v2_5:cjVigY5qzO86Huf0OWal": // Eric
            return "elevenlabs-roger"
            
        // OpenAI Realtime voices - prefix with "openai-"
        case "alloy", "echo", "fable", "onyx", "nova", "shimmer":
            return "openai-\(voice.id)"
            
        // Default: try to use the voice ID as-is (for backwards compatibility)
        default:
            return voice.id.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
        }
    }
    
    /// Get preview audio URL (pre-generated static file)
    private func generatePreview(voice: TTSVoice) async throws -> URL {
        let configuration = Configuration.shared

        // Determine file extension based on provider
        let fileExtension: String
        let voiceFileName: String

        switch voice.provider {
        case .cartesia:
            fileExtension = "wav"
            voiceFileName = getPreviewFileName(for: voice)
        case .elevenlabs:
            fileExtension = "mp3"
            voiceFileName = getPreviewFileName(for: voice)
        case .openaiRealtime:
            // OpenAI Realtime voices use simple IDs like "alloy", "echo", etc.
            fileExtension = "mp3"
            voiceFileName = getPreviewFileName(for: voice)
        }

        // Construct URL to static preview file
        // Use the API endpoint that serves static files
        guard let baseURL = URL(string: configuration.apiBaseURL) else {
            throw VoicePreviewError.invalidURL
        }

        // Get base URL without /v1 suffix
        var basePath = baseURL.absoluteString
        if basePath.hasSuffix("/v1") {
            basePath = String(basePath.dropLast(3))
        }
        // Ensure no trailing slash
        if basePath.hasSuffix("/") {
            basePath = String(basePath.dropLast())
        }

        // Use the static file endpoint: /voice-previews/{voiceId}.{ext}
        guard let previewURL = URL(string: "\(basePath)/voice-previews/\(voiceFileName).\(fileExtension)") else {
            throw VoicePreviewError.invalidURL
        }

        // Check if file already exists in cache
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let cacheSubDir = cacheDir.appendingPathComponent("voice-previews", isDirectory: true)
        
        // Create cache directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheSubDir, withIntermediateDirectories: true)
        
        let fileName = "\(voiceFileName)-preview.\(fileExtension)"
        let cachedFileURL = cacheSubDir.appendingPathComponent(fileName)
        
        // If file already exists locally, use it
        if FileManager.default.fileExists(atPath: cachedFileURL.path) {
            return cachedFileURL
        }
        
        // Download and cache the preview file
        let (data, response) = try await URLSession.shared.data(from: previewURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("❌ Failed to download preview: HTTP \(statusCode) from \(previewURL.absoluteString)")
            throw VoicePreviewError.generationFailed
        }

        // Save to cache directory for persistent storage
        try data.write(to: cachedFileURL)
        print("✅ Cached preview: \(fileName) (\(data.count) bytes)")
        return cachedFileURL
    }
}

extension VoicePreviewService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            // Find and remove the finished player
            if let voiceId = playingVoiceId, audioPlayers[voiceId] === player {
                audioPlayers[voiceId] = nil
                playingVoiceId = nil
            }
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            if let voiceId = playingVoiceId, audioPlayers[voiceId] === player {
                audioPlayers[voiceId] = nil
                playingVoiceId = nil
            }
        }
    }
}

enum VoicePreviewError: LocalizedError {
    case invalidURL
    case generationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid preview URL"
        case .generationFailed:
            return "Failed to generate voice preview"
        }
    }
}

