//
//  Session.swift
//  AI Voice Copilot
//

import Foundation

struct Session: Identifiable, Codable {
    let id: String
    let userId: String
    let context: SessionContext
    let startedAt: Date
    var endedAt: Date?
    let loggingEnabledSnapshot: Bool
    var summaryStatus: SummaryStatus
    var durationMinutes: Int?

    enum SessionContext: String, Codable {
        case carplay
        case phone
    }

    enum SummaryStatus: String, Codable {
        case pending
        case ready
        case failed
    }
}

struct SessionSummary: Codable {
    let id: String
    let sessionId: String
    let title: String
    let summaryText: String
    let actionItems: [String]
    let tags: [String]
    let createdAt: Date
}

struct Turn: Identifiable, Codable {
    let id: String
    let sessionId: String
    let timestamp: Date
    let speaker: Speaker
    let text: String

    enum Speaker: String, Codable {
        case user
        case assistant
    }
}

struct SessionListItem: Identifiable, Codable {
    let id: String
    let title: String
    let summarySnippet: String
    let startedAt: Date
    let endedAt: Date?
    let context: Session.SessionContext?
    
    init(id: String, title: String, summarySnippet: String, startedAt: Date, endedAt: Date?, context: Session.SessionContext? = nil) {
        self.id = id
        self.title = title
        self.summarySnippet = summarySnippet
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.context = context
    }
}

struct StartSessionResponse: Codable {
    let sessionId: String
    let livekitUrl: String
    let livekitToken: String
    let roomName: String
}

