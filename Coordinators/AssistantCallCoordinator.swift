//
//  AssistantCallCoordinator.swift
//  AI Voice Copilot
//

import Foundation
import Combine

enum CallState {
    case idle
    case connecting
    case connected
    case disconnecting
}

@MainActor
class AssistantCallCoordinator: ObservableObject {
    static let shared = AssistantCallCoordinator()

    @Published var callState: CallState = .idle
    @Published var currentSessionID: String?
    @Published var errorMessage: String?

    private let callManager = CallManager.shared
    private let liveKitService = LiveKitService.shared
    private let cloudKit = CloudKitSyncService.shared
    private let sessionLogger = SessionLogger.shared
    private let appCoordinator = AppCoordinator.shared
    private var cancellables = Set<AnyCancellable>()

    // Store the context for when the call connects
    private var pendingContext: Session.SessionContext?

    // Track call start time for duration calculation
    private var callStartTime: Date?

    // Inactivity and max duration timers
    private var inactivityTimer: Timer?
    private var maxDurationTimer: Timer?
    private var lastActivityTime: Date?

    // Constants
    private let inactivityTimeout: TimeInterval = 5 * 60  // 5 minutes
    private let maxCallDuration: TimeInterval = 60 * 60   // 1 hour

    private init() {
        callManager.delegate = self
        liveKitService.delegate = self
    }
    
    func startAssistantCall(context: String, enableLogging: Bool) {
        guard callState == .idle else { return }

        // Update logging setting
        UserSettings.shared.loggingEnabled = enableLogging

        // Parse context string to SessionContext enum
        let sessionContext: Session.SessionContext = (context.lowercased() == "carplay") ? .carplay : .phone
        pendingContext = sessionContext

        callState = .connecting
        errorMessage = nil

        // Start CallKit call
        callManager.startAssistantCall()
    }
    
    func endAssistantCall() {
        guard callState != .idle else { return }

        callState = .disconnecting
        errorMessage = nil

        // Stop timers
        stopTimers()

        // Calculate call duration
        let durationMinutes: Int? = {
            guard let startTime = callStartTime else { return nil }
            let duration = Date().timeIntervalSince(startTime)
            return Int(ceil(duration / 60.0))
        }()

        // Store session ID before clearing it so we can navigate to it
        let completedSessionID = currentSessionID

        // Navigate to the session details immediately so the user sees progress
        if let sessionID = completedSessionID {
            appCoordinator.navigate(to: .sessionDetail(sessionID))
        }

        // End LiveKit connection first
        liveKitService.disconnect()

        // End CallKit call
        callManager.endCurrentCall()

        // End session on backend and sync to CloudKit
        if let sessionID = currentSessionID {
            Task {
                do {
                    try await sessionLogger.endSession(sessionID: sessionID, durationMinutes: durationMinutes)

                    // Update in CloudKit if available
                    if await cloudKit.isICloudAvailable(),
                       let session = try? await cloudKit.fetchSession(id: sessionID) {
                        var updatedSession = session
                        updatedSession.endedAt = Date()
                        updatedSession.durationMinutes = durationMinutes

                        try? await cloudKit.saveSession(updatedSession)
                    }

                    // Nothing else to do here - navigation already happened
                } catch {
                    await MainActor.run {
                        errorMessage = "Failed to end session: \(error.localizedDescription)"
                        print("Failed to end session: \(error)")
                    }
                }
            }
            currentSessionID = nil
        }

        pendingContext = nil
        callStartTime = nil
        lastActivityTime = nil
        callState = .idle
    }

    private func startTimers() {
        lastActivityTime = Date()

        // Start inactivity timer (checks every 30 seconds)
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkInactivity()
            }
        }

        // Start max duration timer (1 hour)
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: maxCallDuration, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                print("⏰ Max call duration reached (1 hour), ending call")
                self?.endAssistantCall()
            }
        }
    }

    private func stopTimers() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
    }

    private func resetInactivityTimer() {
        lastActivityTime = Date()
    }

    private func checkInactivity() {
        guard let lastActivity = lastActivityTime else { return }

        let timeSinceActivity = Date().timeIntervalSince(lastActivity)
        if timeSinceActivity >= inactivityTimeout {
            print("⏰ Inactivity timeout reached (5 minutes), ending call")
            endAssistantCall()
        }
    }
    
    private func handleCallConnected() {
        // Use the stored context from when the call was initiated
        guard let context = pendingContext else {
            // Fallback to phone if context wasn't set (shouldn't happen)
            pendingContext = .phone
            handleCallConnected()
            return
        }

        Task {
            do {
                // Start session and get LiveKit credentials
                let response = try await sessionLogger.startSession(context: context)

                // Sync to CloudKit if available
                if await cloudKit.isICloudAvailable() {
                    let session = Session(
                        id: response.sessionId,
                        userId: "", // Will be set from backend response or iCloud user ID
                        context: context,
                        startedAt: Date(),
                        endedAt: nil,
                        loggingEnabledSnapshot: UserSettings.shared.loggingEnabled,
                        summaryStatus: .pending
                    )
                    try? await cloudKit.saveSession(session)
                }

                // Connect to LiveKit
                await MainActor.run {
                    currentSessionID = response.sessionId
                    callStartTime = Date()
                    startTimers()
                    liveKitService.connect(
                        sessionID: response.sessionId,
                        url: response.livekitUrl,
                        token: response.livekitToken
                    )
                }
            } catch {
                await MainActor.run {
                    callState = .idle
                    pendingContext = nil
                    errorMessage = "Failed to start session: \(error.localizedDescription)"
                    print("Failed to start session: \(error)")
                }
            }
        }
    }
}

extension AssistantCallCoordinator: CallManagerDelegate {
    nonisolated func callManagerDidConnect() {
        Task { @MainActor in
            handleCallConnected()
        }
    }

    nonisolated func callManagerDidDisconnect() {
        Task { @MainActor in
            endAssistantCall()
        }
    }

    nonisolated func callManagerDidFail(error: Error) {
        Task { @MainActor in
            callState = .idle
            pendingContext = nil
            errorMessage = "Call failed: \(error.localizedDescription)"
            print("Call failed: \(error)")
        }
    }
}

extension AssistantCallCoordinator: LiveKitServiceDelegate {
    func liveKitServiceDidConnect() {
        callState = .connected
    }

    func liveKitServiceDidDisconnect() {
        // LiveKit disconnected, but call might still be active
        // Don't change state here - let CallManager handle it
    }
    
    func liveKitServiceDidFail(error: Error) {
        // If LiveKit fails, end the call
        print("❌ LiveKit service failed with error: \(error)")
        print("❌ Error type: \(type(of: error))")
        print("❌ Error description: \(error.localizedDescription)")
        errorMessage = "Connection failed: \(error.localizedDescription)"
        endAssistantCall()
    }

    func liveKitServiceDidDetectActivity() {
        resetInactivityTimer()
    }
}
