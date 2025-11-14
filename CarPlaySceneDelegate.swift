//
//  CarPlaySceneDelegate.swift
//  AI Voice Copilot
//

import Foundation
import UIKit
import CarPlay
import Combine

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var listTemplate: CPListTemplate?
    private var callStateObserver: AnyCancellable?
    private var sessionsObserver: AnyCancellable?
    
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        setupCarPlayUI()
        observeCallState()
        observeSessions()
    }
    
    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        callStateObserver?.cancel()
        sessionsObserver?.cancel()
    }

    private func setupCarPlayUI() {
        updateCarPlayUI()
    }
    
    private func observeCallState() {
        callStateObserver = AssistantCallCoordinator.shared.$callState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateCarPlayUI()
            }
    }
    
    private func observeSessions() {
        sessionsObserver = HybridSessionLogger.shared.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateCarPlayUI()
            }
    }
    
    private func updateCarPlayUI() {
        let callCoordinator = AssistantCallCoordinator.shared
        let hybridLogger = HybridSessionLogger.shared
        
        // Main action item - dynamically updates based on call state
        let mainActionItem = CPListItem(
            text: callStateText(callCoordinator.callState),
            detailText: callStateDetailText(callCoordinator.callState),
            image: callStateImage(callCoordinator.callState)
        )
        
        mainActionItem.handler = { (item: any CPSelectableListItem, completion: @escaping () -> Void) in
            Task { @MainActor in
                let callCoordinator = AssistantCallCoordinator.shared
                if callCoordinator.callState == .idle {
                    let enableLogging = UserSettings.shared.loggingEnabled
                    callCoordinator.startAssistantCall(context: "carplay", enableLogging: enableLogging)
                } else {
                    callCoordinator.endAssistantCall()
                }
                completion()
            }
        }
        
        let actionsSection = CPListSection(items: [mainActionItem], header: "Actions", sectionIndexTitle: nil)
        
        // Recent sessions section (limit to 5 most recent CarPlay sessions)
        var recentSessions: [CPListItem] = []
        let carPlaySessions = hybridLogger.sessions
            .filter { session in
                guard let context = session.context else { return false }
                return context == Session.SessionContext.carplay
            }
            .prefix(5)
        
        for session in carPlaySessions {
            let sessionItem = CPListItem(
                text: session.title.isEmpty ? "Session" : session.title,
                detailText: formatSessionDetail(session),
                image: createSessionImage()
            )
            
            sessionItem.handler = { (item: any CPSelectableListItem, completion: @escaping () -> Void) in
                // Navigate to session detail would go here if CarPlay supported it
                completion()
            }
            
            recentSessions.append(sessionItem)
        }
        
        var sections: [CPListSection] = [actionsSection]
        
        if !recentSessions.isEmpty {
            let sessionsSection = CPListSection(
                items: recentSessions,
                header: "Recent Sessions",
                sectionIndexTitle: nil
            )
            sections.append(sessionsSection)
        }
        
        let newListTemplate = CPListTemplate(title: "Shaw", sections: sections)
        
        // Always recreate the template since updateListTemplate doesn't exist
        listTemplate = newListTemplate
        interfaceController?.setRootTemplate(newListTemplate, animated: true) { success, error in
            if let error = error {
                print("Error setting CarPlay root template: \(error)")
            }
        }
    }
    
    private func callStateText(_ state: CallState) -> String {
        switch state {
        case .idle:
            return "Start Conversation"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "End Conversation"
        case .disconnecting:
            return "Disconnecting..."
        }
    }
    
    private func callStateDetailText(_ state: CallState) -> String? {
        switch state {
        case .idle:
            return "Talk hands-free with your AI assistant"
        case .connecting:
            return "Establishing connection..."
        case .connected:
            return "Tap to end the conversation"
        case .disconnecting:
            return "Ending conversation..."
        }
    }
    
    private func callStateImage(_ state: CallState) -> UIImage? {
        let imageName: String
        switch state {
        case .idle:
            imageName = "mic.fill"
        case .connecting, .disconnecting:
            imageName = "hourglass"
        case .connected:
            imageName = "phone.down.fill"
        }
        
        return UIImage(systemName: imageName)
    }
    
    private func formatSessionDetail(_ session: SessionListItem) -> String {
        var details: [String] = []
        
        if let endedAt = session.endedAt {
            let duration = calculateDuration(startedAt: session.startedAt, endedAt: endedAt)
            if let durationText = duration {
                details.append(durationText)
            }
        }
        
        let relativeTime = formatRelativeTime(session.startedAt)
        details.append(relativeTime)
        
        return details.joined(separator: " • ")
    }
    
    private func calculateDuration(startedAt: Date, endedAt: Date) -> String? {
        let duration = endedAt.timeIntervalSince(startedAt)
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else if seconds > 0 {
            return "\(seconds)s"
        }
        return nil
    }
    
    private func createSessionImage() -> UIImage? {
        return UIImage(systemName: "waveform")
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        
        // If same day, show time only
        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return timeFormatter.string(from: date)
        }
        
        // If yesterday
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        
        // If within last week, show day name
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.dateFormat = "EEEE"
            return weekdayFormatter.string(from: date)
        }
        
        // Otherwise use relative formatter
        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.unitsStyle = .full
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }
}
