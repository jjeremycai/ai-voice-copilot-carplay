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

    @Published var sessions: [SessionListItem] = []
    @Published var isLoading = false
    @Published var error: Error?

    private init() {
        Task {
            await loadSessions()
        }
    }

    // MARK: - Session Lifecycle

    func startSession(context: Session.SessionContext) async throws -> String {
        // Check entitlements first
        await SubscriptionManager.shared.refreshEntitlementsAndSync()

        // Backend will enforce entitlement check, but we can show better UX by checking locally first
        if !SubscriptionManager.shared.state.isActive {
            // Backend will return proper error with free tier info if applicable
        }

        // Always track on backend for usage/billing
        let response = try await backend.startSession(context: context)

        // If CloudKit available, create session there too
        if await cloudKit.isICloudAvailable() {
            let session = Session(
                id: response.sessionId,
                userId: "", // Will be set from backend response or iCloud user ID
                context: context,
                startedAt: Date(),
                endedAt: nil,
                loggingEnabledSnapshot: settings.loggingEnabled,
                summaryStatus: .pending
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
            updatedSession.endedAt = Date()

            try? await cloudKit.saveSession(updatedSession)
        }

        // Reload to show updated session
        await loadSessions()
    }

    // MARK: - Fetching Sessions

    func loadSessions() async {
        isLoading = true
        error = nil

        do {
            // Try CloudKit first (instant, offline-capable)
            if await cloudKit.isICloudAvailable() {
                let cloudKitSessions = try await cloudKit.fetchSessions()
                // Convert Session to SessionListItem
                sessions = cloudKitSessions.map { session in
                    SessionListItem(
                        id: session.id,
                        title: "Session", // Title will come from summary
                        summarySnippet: session.context.rawValue.capitalized,
                        startedAt: session.startedAt,
                        endedAt: session.endedAt,
                        context: session.context
                    )
                }
            } else {
                // Fallback to backend
                sessions = try await backend.fetchSessions()
            }

            isLoading = false
        } catch {
            if error is CancellationError {
                isLoading = false
                return
            }
            self.error = error
            isLoading = false

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

        // Fallback to backend detail (returns session metadata)
        if let detail = try? await backend.fetchSessionDetail(sessionID: id) {
            return detail.session
        }

        return nil
    }

    // MARK: - Deletion

    func deleteSession(id: String) async throws {
        // Delete from both
        try await backend.deleteSession(sessionID: id)

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
