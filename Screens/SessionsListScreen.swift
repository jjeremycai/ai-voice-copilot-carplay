//
//  SessionsListScreen.swift
//  AI Voice Copilot
//

import SwiftUI

struct SessionsListScreen: View {
    @State private var sessions: [SessionListItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @ObservedObject var appCoordinator = AppCoordinator.shared
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading sessions...")
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        loadSessions()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if sessions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No sessions yet")
                        .font(.headline)
                    Text("Start a call to create your first session")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                List(sessions) { session in
                    NavigationLink(value: session.id) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(session.title)
                                .font(.headline)

                            if !session.summarySnippet.isEmpty {
                                Text(session.summarySnippet)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }

                            HStack {
                                Image(systemName: "clock")
                                    .font(.caption)
                                Text(formatDate(session.startedAt))
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: String.self) { sessionID in
            SessionDetailScreen(sessionID: sessionID)
        }
        .onAppear {
            loadSessions()
        }
    }
    
    private func loadSessions() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetchedSessions = try await SessionLogger.shared.fetchSessions()
                await MainActor.run {
                    self.sessions = fetchedSessions
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load sessions: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    SessionsListScreen()
}

