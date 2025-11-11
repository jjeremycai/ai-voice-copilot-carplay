//
//  CloudKitSyncService.swift
//  Shaw
//

import Foundation
import CloudKit

@MainActor
class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()

    private let container: CKContainer
    private let privateDatabase: CKDatabase

    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?

    enum SyncStatus {
        case idle
        case syncing
        case success
        case error(String)
    }

    private init() {
        self.container = CKContainer.default()
        self.privateDatabase = container.privateCloudDatabase

        // Subscribe to remote changes
        Task {
            await subscribeToChanges()
        }
    }

    // MARK: - Session Operations

    func saveSession(_ session: Session) async throws {
        let record = try sessionToRecord(session)
        try await privateDatabase.save(record)
    }

    func fetchSessions() async throws -> [Session] {
        let query = CKQuery(recordType: "Session", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: false)]

        let (results, _) = try await privateDatabase.records(matching: query)

        return try results.compactMap { (_, result) in
            switch result {
            case .success(let record):
                return try recordToSession(record)
            case .failure:
                return nil
            }
        }
    }

    func fetchSession(id: String) async throws -> Session? {
        let recordID = CKRecord.ID(recordName: id)

        do {
            let record = try await privateDatabase.record(for: recordID)
            return try recordToSession(record)
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                return nil
            }
            throw error
        }
    }

    func deleteSession(id: String) async throws {
        let recordID = CKRecord.ID(recordName: id)
        try await privateDatabase.deleteRecord(withID: recordID)
    }

    func deleteAllSessions() async throws {
        let sessions = try await fetchSessions()

        for session in sessions {
            try await deleteSession(id: session.id)
        }
    }

    // MARK: - Conversion Helpers

    private func sessionToRecord(_ session: Session) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: session.id)
        let record = CKRecord(recordType: "Session", recordID: recordID)

        record["startTime"] = session.startTime as CKRecordValue
        record["endTime"] = session.endTime as CKRecordValue?
        record["duration"] = session.duration as CKRecordValue
        record["context"] = session.context.rawValue as CKRecordValue
        record["title"] = session.title as CKRecordValue?
        record["summary"] = session.summary as CKRecordValue?
        record["model"] = session.model as CKRecordValue?
        record["voice"] = session.voice as CKRecordValue?

        // Store transcript as JSON
        if let transcriptData = try? JSONEncoder().encode(session.transcript) {
            record["transcript"] = String(data: transcriptData, encoding: .utf8) as CKRecordValue?
        }

        return record
    }

    private func recordToSession(_ record: CKRecord) throws -> Session {
        guard let startTime = record["startTime"] as? Date,
              let duration = record["duration"] as? Int,
              let contextString = record["context"] as? String,
              let context = Session.SessionContext(rawValue: contextString) else {
            throw CloudKitError.invalidRecord
        }

        let endTime = record["endTime"] as? Date
        let title = record["title"] as? String
        let summary = record["summary"] as? String
        let model = record["model"] as? String
        let voice = record["voice"] as? String

        // Decode transcript from JSON
        var transcript: [Session.TranscriptEntry] = []
        if let transcriptString = record["transcript"] as? String,
           let transcriptData = transcriptString.data(using: .utf8) {
            transcript = (try? JSONDecoder().decode([Session.TranscriptEntry].self, from: transcriptData)) ?? []
        }

        return Session(
            id: record.recordID.recordName,
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            context: context,
            title: title,
            summary: summary,
            transcript: transcript,
            model: model,
            voice: voice
        )
    }

    // MARK: - Subscriptions for Real-time Sync

    private func subscribeToChanges() async {
        let subscription = CKQuerySubscription(
            recordType: "Session",
            predicate: NSPredicate(value: true),
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            try await privateDatabase.save(subscription)
        } catch {
            print("Failed to subscribe to changes: \(error)")
        }
    }

    // MARK: - Account Status

    func checkAccountStatus() async throws -> CKAccountStatus {
        return try await container.accountStatus()
    }

    func isICloudAvailable() async -> Bool {
        do {
            let status = try await checkAccountStatus()
            return status == .available
        } catch {
            return false
        }
    }
}

enum CloudKitError: LocalizedError {
    case invalidRecord
    case notAvailable
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidRecord:
            return "Invalid CloudKit record"
        case .notAvailable:
            return "iCloud is not available. Please sign in to iCloud in Settings."
        case .unauthorized:
            return "Not authorized to access iCloud"
        }
    }
}
