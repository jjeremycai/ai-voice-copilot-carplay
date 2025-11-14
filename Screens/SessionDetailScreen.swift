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
    @State private var showShareSummary = false
    @State private var showShareTranscript = false
    @State private var showSuccessMessage = false
    @State private var successMessage = ""
    @ObservedObject var appCoordinator = AppCoordinator.shared
    @StateObject private var hybridLogger = HybridSessionLogger.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isLoading {
                    ProgressView("Loading session details...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: error.contains("not found") ? "xmark.circle" : "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        if error.contains("not found") {
                            // Session doesn't exist - show go back button
                            Button("Go Back") {
                                appCoordinator.navigateBack()
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            // Other error - show retry button
                            Button("Retry") {
                                loadSessionDetails()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding()
                } else {
                    if let summary = summary {
                        SummarySection(
                            summary: summary,
                            sessionID: sessionID,
                            onTitleUpdated: { newTitle in
                                if var updatedSummary = self.summary {
                                    updatedSummary = SessionSummary(
                                        id: updatedSummary.id,
                                        sessionId: updatedSummary.sessionId,
                                        title: newTitle,
                                        summaryText: updatedSummary.summaryText,
                                        actionItems: updatedSummary.actionItems,
                                        tags: updatedSummary.tags,
                                        createdAt: updatedSummary.createdAt
                                    )
                                    self.summary = updatedSummary
                                }
                            }
                        )
                    } else if let session = session {
                        ProcessingSummaryView(status: session.summaryStatus)
                    }
                    
                    if !turns.isEmpty {
                        TranscriptSection(turns: turns)
                    } else if let session = session {
                        EmptyTranscriptView(session: session)
                    }
                }
            }
            .padding()
        }
        .refreshable {
            HapticFeedbackService.shared.light()
            loadSessionDetails()
            HapticFeedbackService.shared.success()
        }
        .navigationTitle(summary?.title ?? "Session")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if summary != nil {
                        Button(action: {
                            showShareSummary = true
                        }) {
                            Label("Share Summary", systemImage: "square.and.arrow.up")
                        }
                    }

                    if !turns.isEmpty {
                        Button(action: {
                            showShareTranscript = true
                        }) {
                            Label("Copy Transcript", systemImage: "doc.on.clipboard")
                        }
                    }

                    Divider()

                    Button(role: .destructive, action: {
                        HapticFeedbackService.shared.heavy()
                        showDeleteConfirmation = true
                    }) {
                        Label("Delete Session", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showShareSummary) {
            if let summary = summary {
                ShareSheet(items: [formatSummaryText(summary)])
            }
        }
        .sheet(isPresented: $showShareTranscript) {
            ShareSheet(items: [formatTranscriptText(turns)])
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
                let detail = try await SessionLogger.shared.fetchSessionDetailWithRetry(sessionID: sessionID)
                let summaryPresent = detail.summary != nil
                let turnsCount = detail.turns.count
                let firstTurnPreview = detail.turns.first?.text.prefix(80) ?? ""
                print("📄 Detail fetched — summary: \(summaryPresent), turns: \(turnsCount), first: \(firstTurnPreview)")
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
                try await hybridLogger.deleteSession(id: sessionID)
                await MainActor.run {
                    HapticFeedbackService.shared.success()
                    appCoordinator.navigateBack()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to delete session: \(error.localizedDescription)"
                    HapticFeedbackService.shared.error()
                }
            }
        }
    }

    private func formatSummaryText(_ summary: SessionSummary) -> String {
        var text = "\(summary.title)\n\n"
        text += "\(summary.summaryText)\n"

        if !summary.actionItems.isEmpty {
            text += "\nAction Items:\n"
            for item in summary.actionItems {
                text += "• \(item)\n"
            }
        }

        if !summary.tags.isEmpty {
            text += "\nTags: \(summary.tags.joined(separator: ", "))\n"
        }

        return text
    }

    private func formatTranscriptText(_ turns: [Turn]) -> String {
        turns.map { turn in
            let timeStr = formatTime(turn.timestamp)
            let speaker = turn.speaker == .user ? "You" : "Assistant"
            return "[\(timeStr)] \(speaker): \(turn.text)"
        }.joined(separator: "\n\n")
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct SummarySection: View {
    let summary: SessionSummary
    let sessionID: String
    let onTitleUpdated: (String) -> Void

    @State private var isEditingTitle = false
    @State private var editedTitle: String = ""
    @State private var isUpdating = false
    @State private var updateError: String?
    @State private var showSuccessMessage = false
    @State private var successMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Summary")
                .font(.title2)
                .fontWeight(.bold)

            HStack {
                if isEditingTitle {
                    TextField("Session Title", text: $editedTitle)
                        .font(.headline)
                        .textFieldStyle(.roundedBorder)

                    if isUpdating {
                        ProgressView()
                    } else {
                        Button("Save") {
                            HapticFeedbackService.shared.medium()
                            updateTitle()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(editedTitle.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button("Cancel") {
                            isEditingTitle = false
                            editedTitle = summary.title
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text(summary.title)
                        .font(.headline)

                    Spacer()

                    Button(action: {
                        editedTitle = summary.title
                        isEditingTitle = true
                    }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.blue)
                    }
                }
            }

                if let error = updateError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                if showSuccessMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(successMessage)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .transition(.opacity.combined(with: .scale))
                }

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
        .animation(.easeInOut(duration: 0.2), value: showSuccessMessage)
        .animation(.easeInOut(duration: 0.2), value: updateError)
    }

    private func updateTitle() {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        isUpdating = true
        updateError = nil

        Task {
            do {
                guard let url = URL(string: "\(Configuration.shared.apiBaseURL)/sessions/\(sessionID)/title") else {
                    throw URLError(.badURL)
                }

                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                if let token = AuthService.shared.authToken {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }

                let body = ["title": trimmedTitle]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (_, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                await MainActor.run {
                    onTitleUpdated(trimmedTitle)
                    isEditingTitle = false
                    isUpdating = false
                    updateError = nil
                    showSuccessMessage = true
                    successMessage = "Title updated"
                    HapticFeedbackService.shared.success()
                    
                    // Hide success message after 2 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await MainActor.run {
                            showSuccessMessage = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    updateError = "Failed to update title: \(error.localizedDescription)"
                    isUpdating = false
                    HapticFeedbackService.shared.error()
                }
            }
        }
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
                HStack(spacing: 4) {
                    if session.summaryStatus == .pending {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 12, height: 12)
                    }
                    Text(statusDescription.text)
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(statusDescription.color.opacity(0.15))
                .foregroundColor(statusDescription.color)
                .cornerRadius(8)
                .animation(.easeInOut(duration: 0.3), value: session.summaryStatus)
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

                if let duration = session.durationMinutes {
                    Label("\(duration) minute\(duration == 1 ? "" : "s")", systemImage: "timer")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct EmptyTranscriptView: View {
    let session: Session

    private var message: String {
        if session.endedAt == nil {
            return "Transcript will appear as you talk. The conversation is still in progress."
        } else {
            return "We haven't received transcript turns yet. This can take a few moments after the call ends—pull to refresh if it takes longer than expected."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcript")
                .font(.title2)
                .fontWeight(.bold)

            Text(message)
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

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        SessionDetailScreen(sessionID: "test-id")
    }
}
