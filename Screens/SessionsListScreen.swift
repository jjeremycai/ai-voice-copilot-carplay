//
//  SessionsListScreen.swift
//  AI Voice Copilot
//

import SwiftUI

struct SessionsListScreen: View {
    @StateObject private var hybridLogger = HybridSessionLogger.shared
    @ObservedObject var appCoordinator = AppCoordinator.shared
    
    var body: some View {
        Group {
            if hybridLogger.isLoading {
                ProgressView("Loading sessions...")
            } else if let error = hybridLogger.error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(error.localizedDescription)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task {
                            await hybridLogger.loadSessions()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if hybridLogger.sessions.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No sessions yet")
                        .font(.headline)
                    Text("Start a call to create your first session")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button(action: {
                        HapticFeedbackService.shared.medium()
                        appCoordinator.selectedTab = 0
                    }) {
                        Label("Start Your First Call", systemImage: "phone.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                List(hybridLogger.sessions) { session in
                    NavigationLink(value: session.id) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(session.title)
                                    .font(.headline)
                                Spacer()
                                if let endedAt = session.endedAt, let duration = calculateDuration(startedAt: session.startedAt, endedAt: endedAt) {
                                    Text(duration)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color(.systemGray5))
                                        .cornerRadius(4)
                                }
                            }

                            if !session.summarySnippet.isEmpty {
                                Text(session.summarySnippet)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }

                            HStack(spacing: 12) {
                                if let context = session.context {
                                    HStack(spacing: 4) {
                                        Image(systemName: context == .carplay ? "car.fill" : "phone.fill")
                                            .font(.caption2)
                                        Text(context.rawValue.capitalized)
                                            .font(.caption)
                                    }
                                    .foregroundColor(.secondary)
                                }
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.caption)
                                    Text(TimeFormatter.shared.relativeTime(from: session.startedAt))
                                        .font(.caption)
                                }
                                .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityLabel("Session: \(session.title)")
                    .accessibilityHint("Double tap to view details")
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            HapticFeedbackService.shared.heavy()
                            Task {
                                try? await hybridLogger.deleteSession(id: session.id)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        
                        Button {
                            HapticFeedbackService.shared.light()
                            // Share functionality would go here
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: String.self) { sessionID in
            SessionDetailScreen(sessionID: sessionID)
        }
        .refreshable {
            HapticFeedbackService.shared.light()
            await hybridLogger.loadSessions()
            HapticFeedbackService.shared.success()
        }
    }

    private func formatDate(_ date: Date) -> String {
        return TimeFormatter.shared.fullDate(date)
    }
    
    private func calculateDuration(startedAt: Date, endedAt: Date) -> String? {
        let duration = endedAt.timeIntervalSince(startedAt)
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        
        if minutes > 0 {
            return "\(minutes)m"
        } else if seconds > 0 {
            return "\(seconds)s"
        }
        return nil
    }
}

#Preview {
    SessionsListScreen()
}

