//
//  HybridSessionLogger.swift
//  Shaw
//
//  Coordinates session storage between CloudKit (for sync) and Backend (for billing)
//

import Foundation

@MainActor
class HybridSessionLogger: ObservableObject {
    static let shared = HybridSessionLogger()

    private let cloudKit = CloudKitSyncService.shared
    private let backend = SessionLogger.shared
    private let settings = UserSettings.shared

    @Published var sessions: [Session] = []
    @Published var isLoading = false
    @Published var error: Error?

    private init() {
        Task {
            await loadSessions()
        }
    }

    // MARK: - Session Lifecycle

    func startSession(context: Session.SessionContext) async throws -> String {
        // Always track on backend for usage/billing
        let response = try await backend.startSession(context: context)

        // If CloudKit available, create session there too
        if await cloudKit.isICloudAvailable() {
            let session = Session(
                id: response.sessionId,
                startTime: Date(),
                endTime: nil,
                duration: 0,
                context: context,
                title: nil,
                summary: nil,
                transcript: [],
                model: settings.selectedModel.rawValue,
                voice: settings.selectedVoice.id
            )

            try? await cloudKit.saveSession(session)
        }

        return response.sessionId
    }

    func endSession(sessionID: String) async throws {
        // End on backend
        try await backend.endSession(sessionID: sessionID)

        // Update in CloudKit if available
        if await cloudKit.isICloudAvailable(),
           let session = try? await cloudKit.fetchSession(id: sessionID) {
            var updatedSession = session
            updatedSession.endTime = Date()
            updatedSession.duration = Int(Date().timeIntervalSince(session.startTime))

            try? await cloudKit.saveSession(updatedSession)
        }

        // Reload to show updated session
        await loadSessions()
    }

    func logTurn(sessionID: String, speaker: Turn.Speaker, text: String, timestamp: Date) {
        guard settings.loggingEnabled else { return }

        // Log to backend (fire and forget)
        backend.logTurn(sessionID: sessionID, speaker: speaker, text: text, timestamp: timestamp)

        // Update CloudKit in background
        Task {
            guard await cloudKit.isICloudAvailable(),
                  var session = try? await cloudKit.fetchSession(id: sessionID) else {
                return
            }

            let entry = Session.TranscriptEntry(
                speaker: speaker,
                text: text,
                timestamp: timestamp
            )
            session.transcript.append(entry)

            try? await cloudKit.saveSession(session)
        }
    }

    // MARK: - Fetching Sessions

    func loadSessions() async {
        isLoading = true
        error = nil

        do {
            // Try CloudKit first (instant, offline-capable)
            if await cloudKit.isICloudAvailable() {
                sessions = try await cloudKit.fetchSessions()
            } else {
                // Fallback to backend
                sessions = try await backend.fetchSessions()
            }

            isLoading = false
        } catch {
            self.error = error
            isLoading = false

            // Try backend as fallback
            if let backendSessions = try? await backend.fetchSessions() {
                sessions = backendSessions
            }
        }
    }

    func fetchSession(id: String) async throws -> Session? {
        // Try CloudKit first (faster)
        if await cloudKit.isICloudAvailable(),
           let session = try? await cloudKit.fetchSession(id: id) {
            return session
        }

        // Fallback to backend
        return try await backend.fetchSession(id: id)
    }

    // MARK: - Deletion

    func deleteSession(id: String) async throws {
        // Delete from both
        try await backend.deleteSession(id: id)

        if await cloudKit.isICloudAvailable() {
            try? await cloudKit.deleteSession(id: id)
        }

        await loadSessions()
    }

    func deleteAllSessions() async throws {
        // Delete from both
        try await backend.deleteAllSessions()

        if await cloudKit.isICloudAvailable() {
            try? await cloudKit.deleteAllSessions()
        }

        sessions = []
    }

    // MARK: - Usage Stats

    func getUsageStats() async throws -> UsageStatsResponse {
        // Usage stats only come from backend
        return try await backend.getUsageStats()
    }

    // MARK: - Sync Status

    func checkSyncStatus() async -> String {
        if await cloudKit.isICloudAvailable() {
            return "Syncing via iCloud"
        } else {
            return "iCloud unavailable - using backend only"
        }
    }
}
