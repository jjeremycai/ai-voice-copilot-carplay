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
    private let sessionLogger = SessionLogger.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Store the context for when the call connects
    private var pendingContext: Session.SessionContext?
    
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
        
        // End LiveKit connection first
        liveKitService.disconnect()
        
        // End CallKit call
        callManager.endCurrentCall()
        
        // End session on backend
        if let sessionID = currentSessionID {
            Task {
                do {
                    try await sessionLogger.endSession(sessionID: sessionID)
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
        callState = .idle
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

                // Connect to LiveKit
                await MainActor.run {
                    currentSessionID = response.sessionId
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
    nonisolated func liveKitServiceDidConnect() {
        Task { @MainActor in
            callState = .connected
        }
    }

    nonisolated func liveKitServiceDidDisconnect() {
        // LiveKit disconnected, but call might still be active
        // Don't change state here - let CallManager handle it
    }
    
    func liveKitServiceDidFail(error: Error) {
        // If LiveKit fails, end the call
        errorMessage = "Connection failed: \(error.localizedDescription)"
        endAssistantCall()
    }
}

