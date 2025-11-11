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
    @StateObject private var hybridLogger = HybridSessionLogger.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var syncStatus: String?
    @State private var isRefreshing = false
    @State private var showRestoreSuccess = false
    @State private var showRestoreError = false
    @State private var restoreErrorMessage: String?
    @State private var showPaywall = false

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Status")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text(subscriptionManager.state.displayStatus)
                            .font(.body)
                            .fontWeight(.semibold)
                    }

                    Spacer()

                    Image(systemName: subscriptionManager.state.isActive ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(subscriptionManager.state.isActive ? .green : .orange)
                        .imageScale(.large)
                }
                .padding(.vertical, 4)

                if let expiresAt = subscriptionManager.state.expiresAt {
                    HStack {
                        Text("Renews")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(formatDate(expiresAt))
                            .font(.caption)
                    }
                }

                if subscriptionManager.state.status == .inactive {
                    Button(action: {
                        showPaywall = true
                    }) {
                        HStack {
                            Image(systemName: "star.fill")
                            Text("Upgrade to Pro")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: {
                        openSubscriptionManagement()
                    }) {
                        HStack {
                            Image(systemName: "gearshape")
                            Text("Manage Subscription")
                        }
                    }
                }

                Button(action: restoreSubscription) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Restore Purchases")
                    }
                }
                .disabled(subscriptionManager.isLoading)
            } header: {
                Text("Subscription")
            } footer: {
                if subscriptionManager.state.status == .inactive {
                    Text("Free users get 10 minutes per month. Upgrade to Pro for unlimited minutes.")
                } else {
                    Text("Manage your subscription or cancel anytime in App Store settings.")
                }
            }
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
                HStack {
                    Image(systemName: syncStatus?.contains("Syncing via iCloud") == true ? "checkmark.icloud" : "icloud.slash")
                        .foregroundColor(syncStatus?.contains("Syncing via iCloud") == true ? .green : .orange)
                        .imageScale(.large)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sync Status")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if let status = syncStatus {
                            Text(status)
                                .font(.body)
                                .foregroundColor(status.contains("Syncing via iCloud") ? .primary : .secondary)
                        } else {
                            Text("Checking...")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 4)

                Button(action: restoreFromiCloud) {
                    HStack {
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Restoring...")
                        } else {
                            Image(systemName: "arrow.clockwise.icloud")
                            Text("Restore from iCloud")
                        }
                    }
                }
                .disabled(isRefreshing || syncStatus?.contains("unavailable") == true)
            } header: {
                Text("Cloud Backup")
            } footer: {
                Text("Sessions automatically sync across all your devices signed into the same iCloud account. Use restore to manually fetch the latest data from iCloud.")
            }

            Section {
                NavigationLink(destination: VoicePickerView(settings: settings)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Selected Voice")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(settings.selectedVoice.name)
                                .font(.body)
                        }
                        Spacer()
                    }
                }
            } header: {
                Text("Assistant Voice")
            } footer: {
                Text("Choose your preferred voice for the assistant. Tap the play button to preview each voice. Visit cartesia.ai/voices for more options.")
            }

            Section {
                Picker("Retention Period", selection: $settings.retentionDays) {
                    Text("Never delete").tag(0)
                    Text("Delete after 7 days").tag(7)
                    Text("Delete after 30 days").tag(30)
                    Text("Delete after 90 days").tag(90)
                    Text("Delete after 180 days").tag(180)
                    Text("Delete after 365 days").tag(365)
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
                Text("Data Retention")
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
        .alert("Restore Complete", isPresented: $showRestoreSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your sessions have been successfully restored from iCloud.")
        }
        .alert("Restore Failed", isPresented: $showRestoreError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreErrorMessage ?? "Failed to restore sessions from iCloud. Please try again.")
        }
        .task {
            loadUsageStats()
            await checkSyncStatus()
        }
        .refreshable {
            loadUsageStats()
            await checkSyncStatus()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private func openSubscriptionManagement() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(url)
    }

    private func restoreSubscription() {
        Task {
            do {
                try await subscriptionManager.restore()
                showRestoreSuccess = true
            } catch {
                restoreErrorMessage = error.localizedDescription
                showRestoreError = true
            }
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
                try await hybridLogger.deleteAllSessions()
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

    private func checkSyncStatus() async {
        let status = await hybridLogger.checkSyncStatus()
        await MainActor.run {
            syncStatus = status
        }
    }

    private func restoreFromiCloud() {
        isRefreshing = true
        restoreErrorMessage = nil

        Task {
            await hybridLogger.loadSessions()
            await MainActor.run {
                isRefreshing = false
                if hybridLogger.error != nil {
                    restoreErrorMessage = hybridLogger.error?.localizedDescription
                    showRestoreError = true
                } else {
                    showRestoreSuccess = true
                }
            }
        }
    }
}

#Preview {
    SettingsScreen()
}
