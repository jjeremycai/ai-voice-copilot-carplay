//
//  LiveKitService.swift
//  AI Voice Copilot
//

import Foundation
import AVFoundation
import LiveKit

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

    private func handleReconnection() {
        guard let room = room else { return }
        Task {
            await subscribeToAssistantAudio(room: room)
        }
    }
}

extension LiveKitService: RoomDelegate {
    func roomDidConnect(_ room: Room) {
        // Connection established
    }

    func room(_ room: Room, didDisconnect error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            self.room = nil
            if let error = error {
                self.delegate?.liveKitServiceDidFail(error: error)
            } else {
                self.delegate?.liveKitServiceDidDisconnect()
            }
        }
    }

    func room(_ room: Room, participant: RemoteParticipant, didSubscribeTo publication: RemoteTrackPublication, track: Track) {
        if publication.kind == .audio {
            // Audio track subscribed successfully
        }
    }
}
