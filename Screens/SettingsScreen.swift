//
//  SettingsScreen.swift
//  Shaw
//

import SwiftUI
import AVFoundation

struct SettingsScreen: View {
    @State private var settings = UserSettings.shared
    @State private var appCoordinator = AppCoordinator.shared
    @State private var showDeleteAllConfirmation = false
    @State private var showDeleteSuccess = false
    @State private var usageStats: UsageStatsResponse?
    @State private var isLoadingUsage = false
    @State private var usageError: String?

    var body: some View {
        Form {
            Section {
                if isLoadingUsage {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading usage...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if let stats = usageStats {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Subscription")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(stats.subscriptionTier.capitalized)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }

                        Divider()

                        HStack {
                            Text("Minutes Used")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(stats.usedMinutes)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }

                        if let remaining = stats.remainingMinutes, let limit = stats.monthlyLimit {
                            HStack {
                                Text("Remaining")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(remaining) / \(limit)")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(remaining < 10 ? .red : .primary)
                            }

                            // Progress bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color(.systemGray5))
                                        .frame(height: 6)
                                        .cornerRadius(3)

                                    Rectangle()
                                        .fill(remaining < 10 ? Color.red : Color.blue)
                                        .frame(
                                            width: min(geometry.size.width, geometry.size.width * CGFloat(stats.usedMinutes) / CGFloat(limit)),
                                            height: 6
                                        )
                                        .cornerRadius(3)
                                }
                            }
                            .frame(height: 6)
                        } else if stats.monthlyLimit == nil {
                            // Unlimited plan
                            HStack {
                                Text("Remaining")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Unlimited")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                            }
                        }

                        Divider()

                        HStack {
                            Text("Billing Period")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(formatDate(stats.billingPeriodStart))
                                    .font(.caption)
                                Text("to")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(formatDate(stats.billingPeriodEnd))
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } else if let error = usageError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Failed to load usage: \(error)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button(action: {
                        loadUsageStats()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Load Usage Statistics")
                        }
                    }
                }
            } header: {
                Text("Usage & Billing")
            } footer: {
                if usageStats != nil {
                    Text("Usage resets at the start of each billing period.")
                }
            }

            Section {
                NavigationLink(destination: ModelPickerView(settings: settings)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Model")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(settings.selectedModel.displayName)
                                .font(.body)
                        }
                        Spacer()
                    }
                }

                Text("The selected model will be used for all new assistant calls.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("AI Assistant")
            } footer: {
                Text("Different models offer varying balances of speed, quality, and cost. Changes take effect on your next call.")
            }

            Section {
                NavigationLink(destination: VoicePickerView(settings: settings)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Voice")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(settings.selectedVoice.name)
                                .font(.body)
                        }
                        Spacer()
                    }
                }
            } header: {
                Text("Voice")
            } footer: {
                Text("Choose your preferred voice for the assistant. Tap the play button to preview each voice. Visit cartesia.ai/voices for more options.")
            }

            Section {
                Picker("Delete After", selection: $settings.retentionDays) {
                    Text("Never").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("180 days").tag(180)
                    Text("365 days").tag(365)
                }

                if settings.retentionDays == 0 {
                    Text("Sessions will never be automatically deleted.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Sessions older than \(settings.retentionDays) days will be automatically deleted.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Delete After")
            }

            Section {
                Button(role: .destructive, action: {
                    showDeleteAllConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete All History")
                    }
                }
            } header: {
                Text("Data Management")
            } footer: {
                Text("This will permanently delete all your session history and summaries.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .alert("Delete All History", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                deleteAllSessions()
            }
        } message: {
            Text("Are you sure you want to delete all your session history? This action cannot be undone.")
        }
        .alert("Success", isPresented: $showDeleteSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("All session history has been deleted.")
        }
        .task {
            loadUsageStats()
        }
        .refreshable {
            loadUsageStats()
        }
    }

    private func loadUsageStats() {
        isLoadingUsage = true
        usageError = nil

        Task {
            do {
                let stats = try await SessionLogger.shared.getUsageStats()
                await MainActor.run {
                    usageStats = stats
                    isLoadingUsage = false
                }
            } catch {
                await MainActor.run {
                    usageError = error.localizedDescription
                    isLoadingUsage = false
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func deleteAllSessions() {
        Task {
            do {
                try await SessionLogger.shared.deleteAllSessions()
                await MainActor.run {
                    showDeleteSuccess = true
                }
            } catch {
                await MainActor.run {
                    print("Failed to delete all sessions: \(error)")
                }
            }
        }
    }
}

#Preview {
    SettingsScreen()
}
