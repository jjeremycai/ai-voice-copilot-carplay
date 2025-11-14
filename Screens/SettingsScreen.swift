//
//  SettingsScreen.swift
//  Shaw
//

import SwiftUI
import AVFoundation
import CloudKit

struct SettingsScreen: View {
    @ObservedObject private var settings = UserSettings.shared
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
    @State private var showCapabilitiesInfo = false
    

    var body: some View {
        Form {
            Section {
                // Status Row
                HStack(spacing: 12) {
                    Image(systemName: subscriptionManager.state.isActive ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(subscriptionManager.state.isActive ? .green : .orange)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(subscriptionManager.state.displayStatus)
                            .font(.headline)
                        
                        Text("Subscription Status")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                
                // Usage Stats
                if isLoadingUsage {
                    HStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading usage...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                } else if let stats = usageStats {
                    VStack(alignment: .leading, spacing: 10) {
                        if let remaining = stats.remainingMinutes, let limit = stats.monthlyLimit {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(stats.usedMinutes) / \(limit) minutes")
                                        .font(.headline)
                                        .foregroundColor(remaining < 10 ? .red : .primary)
                                    
                                    Text("\(remaining) remaining")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            
                            // Progress bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color(.systemGray5))
                                        .frame(height: 8)

                                    Capsule()
                                        .fill(remaining < 10 ? Color.red : Color.blue)
                                        .frame(
                                            width: min(geometry.size.width, geometry.size.width * CGFloat(stats.usedMinutes) / CGFloat(limit)),
                                            height: 8
                                        )
                                }
                            }
                            .frame(height: 8)
                        } else if stats.monthlyLimit == nil {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(stats.usedMinutes) minutes used")
                                        .font(.headline)
                                    
                                    Text("Unlimited plan")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "infinity")
                                    .foregroundColor(.green)
                                    .font(.title3)
                            }
                        } else {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(stats.usedMinutes) minutes used")
                                        .font(.headline)
                                }
                                
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                } else if let error = usageError {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Failed to load usage")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        
                        Spacer()
                        
                        Button("Retry") {
                            loadUsageStats()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                } else {
                    Button(action: {
                        loadUsageStats()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Load Usage Statistics")
                        }
                    }
                    .listRowInsets(EdgeInsets())
                }
                
                // Upgrade Button
                if subscriptionManager.state.status == .inactive {
                    Button(action: {
                        showPaywall = true
                    }) {
                        HStack {
                            Image(systemName: "star.fill")
                            Text("Upgrade to Pro")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
                
                // Restore Button
                Button(action: restoreSubscription) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Restore Purchases")
                    }
                }
                .disabled(subscriptionManager.isLoading)
                .padding(.vertical, 12)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            } header: {
                Text("Subscription")
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
                Toggle(isOn: Binding(
                    get: { settings.toolCallingEnabled },
                    set: { newValue in
                        HapticFeedbackService.shared.light()
                        settings.toolCallingEnabled = newValue
                    }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable Tool Calling")
                            .font(.body)
                        Text("Allow assistant to use external tools and capabilities")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if settings.toolCallingEnabled {
                    Toggle(isOn: Binding(
                        get: { settings.webSearchEnabled },
                        set: { newValue in
                            HapticFeedbackService.shared.light()
                            settings.webSearchEnabled = newValue
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Web Search")
                                .font(.body)
                            Text("Search the web for current information, news, and facts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text("Assistant Capabilities")
                    Button(action: {
                        showCapabilitiesInfo = true
                    }) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } footer: {
                if settings.toolCallingEnabled {
                    Text("The assistant can use Perplexity to search the web for real-time information when needed.")
                } else {
                    Text("Tool calling is disabled. The assistant will rely only on its built-in knowledge.")
                }
            }

            Section {
                NavigationLink {
                    List {
                        Picker(selection: $settings.retentionDays) {
                            Text("Never delete").tag(0)
                            Text("Delete after 7 days").tag(7)
                            Text("Delete after 30 days").tag(30)
                            Text("Delete after 90 days").tag(90)
                            Text("Delete after 180 days").tag(180)
                            Text("Delete after 365 days").tag(365)
                        } label: {
                            EmptyView()
                        }
                        .pickerStyle(.inline)
                    }
                    .navigationTitle("Retention Period")
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    HStack {
                        Text("Retention Period")
                        Spacer()
                        Text(retentionPeriodDisplayText)
                            .foregroundColor(.secondary)
                    }
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

                Button(role: .destructive, action: {
                    showDeleteAllConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete All History")
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text("Data Retention")
                    Button(action: {}) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .help("Automatically delete old sessions to save storage space")
                }
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
        .alert("Assistant Capabilities", isPresented: $showCapabilitiesInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Tool calling allows the assistant to use external capabilities like web search. When enabled, the assistant can search the web for real-time information, news, and facts using Perplexity.")
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
                await MainActor.run {
                    showRestoreSuccess = true
                    restoreErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    // Provide a more helpful error message
                    if let subscriptionError = error as? SubscriptionError {
                        restoreErrorMessage = subscriptionError.localizedDescription
                    } else {
                        restoreErrorMessage = "Failed to restore purchases: \(error.localizedDescription)"
                    }
                    showRestoreError = true
                }
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
                    usageError = nil
                }
            } catch {
                await MainActor.run {
                    // Extract a user-friendly error message
                    let errorMessage: String
                    if let sessionError = error as? SessionLoggerError {
                        switch sessionError {
                        case .serverError(let statusCode, let message):
                            if statusCode == 502 {
                                errorMessage = "Server temporarily unavailable. Usage stats will be available when the server is back online."
                            } else {
                                errorMessage = "Server error (\(statusCode)): \(message)"
                            }
                        case .unauthorized:
                            errorMessage = "Authentication required. Please restart the app."
                        default:
                            errorMessage = sessionError.localizedDescription
                        }
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    
                    usageError = errorMessage
                    isLoadingUsage = false
                    // Don't clear existing stats if we have them - show error but keep old data
                }
            }
        }
    }

    private var retentionPeriodDisplayText: String {
        switch settings.retentionDays {
        case 0:
            return "Never delete"
        case 7:
            return "Delete after 7 days"
        case 30:
            return "Delete after 30 days"
        case 90:
            return "Delete after 90 days"
        case 180:
            return "Delete after 180 days"
        case 365:
            return "Delete after 365 days"
        default:
            return "Delete after \(settings.retentionDays) days"
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
            // Check if iCloud is available first
            let cloudKitAvailable = await CloudKitSyncService.shared.isICloudAvailable()
            
            if !cloudKitAvailable {
                await MainActor.run {
                    isRefreshing = false
                    restoreErrorMessage = "iCloud is not available. Please sign in to iCloud in Settings."
                    showRestoreError = true
                }
                return
            }
            
            // Try to load sessions directly from CloudKit (bypass backend fallback)
            do {
                let cloudKitSessions = try await CloudKitSyncService.shared.fetchSessions()
                // Convert to SessionListItem format
                let sessionListItems = cloudKitSessions.map { session in
                    SessionListItem(
                        id: session.id,
                        title: "Session",
                        summarySnippet: session.context.rawValue.capitalized,
                        startedAt: session.startedAt,
                        endedAt: session.endedAt,
                        context: session.context
                    )
                }
                
                await MainActor.run {
                    hybridLogger.sessions = sessionListItems
                    hybridLogger.error = nil // Clear any previous errors
                    isRefreshing = false
                    showRestoreSuccess = true
                    restoreErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    isRefreshing = false
                    // Provide a clear error message for CloudKit failures
                    if let ckError = error as? CKError {
                        switch ckError.code {
                        case .notAuthenticated:
                            restoreErrorMessage = "Please sign in to iCloud in Settings."
                        case .networkUnavailable:
                            restoreErrorMessage = "Network unavailable. Please check your internet connection."
                        default:
                            restoreErrorMessage = "Failed to restore from iCloud: \(ckError.localizedDescription)"
                        }
                    } else {
                        restoreErrorMessage = "Failed to restore from iCloud: \(error.localizedDescription)"
                    }
                    showRestoreError = true
                }
            }
        }
    }
}

#Preview {
    SettingsScreen()
}
