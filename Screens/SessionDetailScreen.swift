//
//  SessionDetailScreen.swift
//  AI Voice Copilot
//

import SwiftUI

struct SessionDetailScreen: View {
    let sessionID: String
    @State private var session: Session?
    @State private var summary: SessionSummary?
    @State private var turns: [Turn] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @ObservedObject var appCoordinator = AppCoordinator.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isLoading {
                    ProgressView("Loading session details...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            loadSessionDetails()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    if let session = session {
                        SessionMetadataSection(session: session)
                    }
                    
                    if let summary = summary {
                        SummarySection(summary: summary)
                    } else if let session = session {
                        ProcessingSummaryView(status: session.summaryStatus)
                    }
                    
                    if !turns.isEmpty {
                        TranscriptSection(turns: turns)
                    } else if let session = session {
                        EmptyTranscriptView(isLoggingEnabled: session.loggingEnabledSnapshot)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive, action: {
                        showDeleteConfirmation = true
                    }) {
                        Label("Delete Session", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Delete Session", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSession()
            }
        } message: {
            Text("Are you sure you want to delete this session? This action cannot be undone.")
        }
        .onAppear {
            loadSessionDetails()
        }
    }
    
    private func loadSessionDetails() {
        isLoading = true
        errorMessage = nil
        session = nil
        summary = nil
        turns = []

        Task {
            do {
                // Add a small delay to allow backend to finish processing the session
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

                let detail = try await SessionLogger.shared.fetchSessionDetail(sessionID: sessionID)
                await MainActor.run {
                    self.session = detail.session
                    self.summary = detail.summary
                    self.turns = detail.turns
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load session: \(error.localizedDescription)"
                    self.isLoading = false
                    print("📡 Session load error: \(error)")
                }
            }
        }
    }
    
    private func deleteSession() {
        Task {
            do {
                try await SessionLogger.shared.deleteSession(sessionID: sessionID)
                await MainActor.run {
                    appCoordinator.navigateBack()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to delete session: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct SummarySection: View {
    let summary: SessionSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Summary")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(summary.title)
                .font(.headline)
            
            Text(summary.summaryText)
                .font(.body)
            
            if !summary.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Action Items")
                        .font(.headline)
                    ForEach(summary.actionItems, id: \.self) { item in
                        HStack(alignment: .top) {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.blue)
                            Text(item)
                                .font(.subheadline)
                        }
                    }
                }
            }
            
            if !summary.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(summary.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(12)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ProcessingSummaryView: View {
    let status: Session.SummaryStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(status == .failed ? "Summary Unavailable" : "Processing Summary")
                .font(.title2)
                .fontWeight(.bold)
            
            switch status {
            case .pending:
                Text("We're still generating the session summary. This usually takes a few moments—pull down to refresh if it takes longer than expected.")
                    .font(.body)
                    .foregroundColor(.secondary)
            case .ready:
                Text("Summary will appear shortly. If it doesn't, try refreshing.")
                    .font(.body)
                    .foregroundColor(.secondary)
            case .failed:
                Text("We couldn't generate a summary for this session. You can still review the transcript below.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct SessionMetadataSection: View {
    let session: Session
    
    private var formattedStartDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: session.startedAt)
    }
    
    private var formattedEndDate: String? {
        guard let endedAt = session.endedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: endedAt)
    }
    
    private var statusDescription: (text: String, color: Color) {
        switch session.summaryStatus {
        case .pending:
            return ("Processing", .orange)
        case .ready:
            return ("Ready", .green)
        case .failed:
            return ("Failed", .red)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Session Info")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Text(statusDescription.text)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusDescription.color.opacity(0.15))
                    .foregroundColor(statusDescription.color)
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Label(session.context.rawValue.capitalized, systemImage: "network")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Label(formattedStartDate, systemImage: "clock")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if let endDate = formattedEndDate {
                    Label("Ended \(endDate)", systemImage: "stopwatch")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Image(systemName: session.loggingEnabledSnapshot ? "checkmark.shield" : "nosign")
                    Text(session.loggingEnabledSnapshot ? "Logging enabled" : "Logging disabled")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct EmptyTranscriptView: View {
    let isLoggingEnabled: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcript")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(isLoggingEnabled
                 ? "We haven't received transcript turns yet. This can take a few moments after the call ends—pull to refresh if it takes longer than expected."
                 : "Transcript history is unavailable because logging was disabled for this call.")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct TranscriptSection: View {
    let turns: [Turn]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcript")
                .font(.title2)
                .fontWeight(.bold)
            
            ForEach(turns) { turn in
                TranscriptBubble(turn: turn)
            }
        }
    }
}

struct TranscriptBubble: View {
    let turn: Turn
    
    var body: some View {
        HStack {
            if turn.speaker == .user {
                Spacer()
            }
            
            VStack(alignment: turn.speaker == .user ? .trailing : .leading, spacing: 4) {
                Text(turn.text)
                    .padding()
                    .background(turn.speaker == .user ? Color.blue : Color(.systemGray5))
                    .foregroundColor(turn.speaker == .user ? .white : .primary)
                    .cornerRadius(16)
                
                Text(formatTime(turn.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: turn.speaker == .user ? .trailing : .leading)
            
            if turn.speaker == .assistant {
                Spacer()
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        SessionDetailScreen(sessionID: "test-id")
    }
}
