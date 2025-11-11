//
//  LiveKitService.swift
//  AI Voice Copilot
//

import Foundation
import AVFoundation
import LiveKit

@MainActor
protocol LiveKitServiceDelegate: AnyObject {
    func liveKitServiceDidConnect()
    func liveKitServiceDidDisconnect()
    func liveKitServiceDidFail(error: Error)
}

final class LiveKitService: @unchecked Sendable {
    static let shared = LiveKitService()

    weak var delegate: LiveKitServiceDelegate?

    private var isConnected = false
    private var sessionId: String?
    private var room: Room?

    private init() {}

    func connect(sessionID: String, url: String, token: String) {
        self.sessionId = sessionID

        Task { @MainActor [weak self] in
            guard let self = self else { return }

            do {
                let room = Room()
                self.room = room

                room.add(delegate: self)

                try await room.connect(url: url, token: token)

                try await self.publishMicrophone(room: room)

                await self.subscribeToAssistantAudio(room: room)

                // Register handler for transcription stream
                await self.registerTranscriptionHandler(room: room, sessionID: sessionID)

                self.isConnected = true
                self.delegate?.liveKitServiceDidConnect()
            } catch {
                self.delegate?.liveKitServiceDidFail(error: error)
            }
        }
    }

    func disconnect() {
        Task { @MainActor [weak self] in
            guard let self = self, let room = self.room else { return }

            await room.disconnect()
            self.room = nil
            self.isConnected = false
            self.sessionId = nil
            self.delegate?.liveKitServiceDidDisconnect()
        }
    }

    private func publishMicrophone(room: Room) async throws {
        try await room.localParticipant.setMicrophone(enabled: true)
    }

    private func subscribeToAssistantAudio(room: Room) async {
        // Audio subscription is automatic in LiveKit
        // RoomDelegate will be notified when tracks are available
    }

    private func registerTranscriptionHandler(room: Room, sessionID: String) async {
        // Register handler for transcription text stream
        await room.registerTextStreamHandler(for: "lk.transcription") { [weak self] stream in
            guard let self = self else { return }

            Task {
                do {
                    // Read transcription segments from the stream
                    for try await segment in stream {
                        await self.handleTranscriptionSegment(segment, sessionID: sessionID)
                    }
                } catch {
                    print("❌ Error reading transcription stream: \(error)")
                }
            }
        }

        print("✅ Registered transcription handler for session \(sessionID)")
    }

    private func handleTranscriptionSegment(_ segment: TextStreamSegment, sessionID: String) async {
        // Extract speaker and text from transcription segment
        guard let participantIdentity = segment.participant?.identity,
              let text = segment.text, !text.isEmpty else {
            return
        }

        // Determine speaker (user or assistant)
        let speaker: Turn.Speaker = participantIdentity.contains("agent") ? .assistant : .user

        print("📝 Transcription [\(speaker.rawValue)]: \(text)")

        // Log the turn to backend
        SessionLogger.shared.logTurn(
            sessionID: sessionID,
            speaker: speaker,
            text: text,
            timestamp: Date()
        )
    }

    private func handleReconnection() {
        guard let room = room else { return }
        Task {
            await subscribeToAssistantAudio(room: room)
        }
    }
}

extension LiveKitService: RoomDelegate {
    nonisolated func roomDidConnect(_ room: Room) {
        Task { @MainActor in
            // Connection established
        }
    }

    nonisolated func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor in
            isConnected = false
            self.room = nil
            if let error = error {
                delegate?.liveKitServiceDidFail(error: error)
            } else {
                delegate?.liveKitServiceDidDisconnect()
            }
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTo publication: RemoteTrackPublication, track: Track) {
        if publication.kind == .audio {
            // Audio track subscribed successfully
        }
    }
}
