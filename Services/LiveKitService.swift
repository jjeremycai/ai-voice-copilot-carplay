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
                print("✅ LiveKit room.connect() completed successfully")
                print("📡 Room state: \(room.connectionState)")

                try await self.publishMicrophone(room: room)

                await self.subscribeToAssistantAudio(room: room)

                self.isConnected = true
                self.delegate?.liveKitServiceDidConnect()
            } catch {
                print("❌ LiveKit connection failed: \(error)")
                print("❌ Error details: \(error.localizedDescription)")
                if let liveKitError = error as? LiveKitError {
                    print("❌ LiveKit error type: \(liveKitError)")
                }
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
