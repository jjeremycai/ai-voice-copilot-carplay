//
//  SessionLogger.swift
//  AI Voice Copilot
//

import Foundation

class SessionLogger {
    static let shared = SessionLogger()

    private let settings = UserSettings.shared
    private let authService = AuthService.shared
    private let configuration = Configuration.shared
    private let urlSession: URLSession
    
    // Dependency injection for testing
    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }
    
    // MARK: - Configuration
    
    private func createDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
    
    // MARK: - Request Helpers
    
    private func createAuthenticatedRequest(url: URL, method: String) -> URLRequest {
        print("📡 createAuthenticatedRequest() - URL: \(url), Method: \(method)")
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add authentication token if available
        if let token = authService.authToken {
            print("📡 Adding auth token to request: \(token.prefix(20))...")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            print("❌ No auth token available for request!")
        }

        return request
    }
    
    private func handleResponse<T: Decodable>(data: Data, response: URLResponse, decoder: JSONDecoder) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid HTTP response")
            throw SessionLoggerError.invalidResponse
        }

        print("📡 Response status code: \(httpResponse.statusCode)")

        // Handle authentication errors
        if httpResponse.statusCode == 401 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            print("❌ 401 Unauthorized - \(errorMessage)")
            throw SessionLoggerError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Server error"
            print("❌ Server error (\(httpResponse.statusCode)): \(errorMessage)")
            throw SessionLoggerError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // Handle empty responses (204 No Content or empty body)
        if data.isEmpty || httpResponse.statusCode == 204 {
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            } else {
                throw SessionLoggerError.invalidResponse
            }
        }
        
        return try decoder.decode(T.self, from: data)
    }
    
    func startSession(context: Session.SessionContext) async throws -> StartSessionResponse {
        print("📡 startSession() called with context: \(context)")
        // Try with current token
        do {
            return try await performStartSession(context: context)
        } catch SessionLoggerError.unauthorized {
            print("⚠️ Unauthorized error, attempting token refresh...")
            // Token expired, try refreshing
            do {
                try await authService.refreshToken()
                print("✅ Token refresh succeeded, retrying request...")
                // Retry with new token
                return try await performStartSession(context: context)
            } catch {
                print("❌ Token refresh failed: \(error)")
                // Refresh failed, throw original unauthorized error
                throw SessionLoggerError.unauthorized
            }
        }
    }

    private func performStartSession(context: Session.SessionContext) async throws -> StartSessionResponse {
        // Ensure we have a valid auth token before making request
        print("📡 Checking authentication before starting session...")
        guard authService.isAuthenticated else {
            print("❌ Not authenticated, cannot start session")
            throw SessionLoggerError.unauthorized
        }

        guard let url = URL(string: "\(configuration.apiBaseURL)/sessions/start") else {
            throw SessionLoggerError.invalidURL
        }

        var request = createAuthenticatedRequest(url: url, method: "POST")

        let settings = UserSettings.shared

        // Extract voice ID (remove provider prefix for backend)
        let voiceId = settings.selectedVoice.id
            .replacingOccurrences(of: "cartesia-", with: "")
            .replacingOccurrences(of: "elevenlabs-", with: "")
            .replacingOccurrences(of: "openai-", with: "")

        let body: [String: Any] = [
            "context": context.rawValue,
            "model": settings.selectedModel.rawValue,
            "voice": voiceId,
            "realtime": settings.useRealtimeMode
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        let decoder = createDecoder()
        return try handleResponse(data: data, response: response, decoder: decoder)
    }
    
    func endSession(sessionID: String, durationMinutes: Int? = nil) async throws {
        guard let url = URL(string: "\(configuration.apiBaseURL)/sessions/end") else {
            throw SessionLoggerError.invalidURL
        }

        var request = createAuthenticatedRequest(url: url, method: "POST")

        var body: [String: Any] = [
            "session_id": sessionID
        ]

        if let durationMinutes = durationMinutes {
            body["duration_minutes"] = durationMinutes
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)

        let decoder = createDecoder()
        let _: EmptyResponse = try handleResponse(data: data, response: response, decoder: decoder)
    }
    
    func logTurn(sessionID: String, speaker: Turn.Speaker, text: String, timestamp: Date) {
        // Only log if logging is enabled
        guard settings.loggingEnabled else { return }
        
        // Fire-and-forget - don't block the call flow
        Task {
            do {
                guard let url = URL(string: "\(configuration.apiBaseURL)/sessions/\(sessionID)/turns") else { return }
                
                var request = createAuthenticatedRequest(url: url, method: "POST")
                
                let formatter = ISO8601DateFormatter()
                let body: [String: Any] = [
                    "speaker": speaker.rawValue,
                    "text": text,
                    "timestamp": formatter.string(from: timestamp)
                ]
                
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                
                _ = try await URLSession.shared.data(for: request)
            } catch {
                // Silently fail - logging should not interrupt the call
                print("Failed to log turn: \(error)")
            }
        }
    }
    
    func fetchSessions() async throws -> [SessionListItem] {
        guard let url = URL(string: "\(configuration.apiBaseURL)/sessions") else {
            throw SessionLoggerError.invalidURL
        }
        
        let request = createAuthenticatedRequest(url: url, method: "GET")
        
        let (data, response) = try await urlSession.data(for: request)
        
        let decoder = createDecoder()
        return try handleResponse(data: data, response: response, decoder: decoder)
    }
    
    func fetchSessionDetail(sessionID: String) async throws -> SessionDetailData {
        guard let url = URL(string: "\(configuration.apiBaseURL)/sessions/\(sessionID)") else {
            throw SessionLoggerError.invalidURL
        }

        let request = createAuthenticatedRequest(url: url, method: "GET")

        let (data, response) = try await urlSession.data(for: request)

        let decoder = createDecoder()

        struct SessionDetailResponse: Codable {
            let session: SessionDTO
            let summary: SessionSummary?
            let turns: [Turn]
        }

        do {
            let detailResponse: SessionDetailResponse = try handleResponse(
                data: data,
                response: response,
                decoder: decoder
            )

            return SessionDetailData(
                session: detailResponse.session.toModel(),
                summary: detailResponse.summary,
                turns: detailResponse.turns
            )
        } catch SessionLoggerError.serverError(let statusCode, let message) where statusCode == 404 {
            print("📡 Session not found (404), likely database was cleared: \(message)")
            throw SessionLoggerError.sessionNotFound
        } catch let decodingError as DecodingError {
            print("📡 Session detail decode failed for combined response, falling back to legacy endpoints: \(decodingError)")

            let sessionData: Data
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sessionDict = jsonObject["session"] as? [String: Any],
               let encodedSession = try? JSONSerialization.data(withJSONObject: sessionDict) {
                sessionData = encodedSession
            } else {
                sessionData = data
            }

            let legacySession = try decoder.decode(SessionDTO.self, from: sessionData).toModel()

            async let turns = fetchSessionTurns(sessionID: sessionID)
            async let summary = fetchSessionSummary(sessionID: sessionID)

            return SessionDetailData(
                session: legacySession,
                summary: try await summary,
                turns: try await turns
            )
        }
    }
    
    func fetchSessionDetailWithRetry(sessionID: String, maxAttempts: Int = 4) async throws -> SessionDetailData {
        var attempt = 0
        var lastError: Error?
        
        while attempt < maxAttempts {
            attempt += 1
            do {
                let detail = try await fetchSessionDetail(sessionID: sessionID)
                
                if shouldRetry(detail: detail, currentAttempt: attempt, maxAttempts: maxAttempts) {
                    let delay = retryDelay(for: attempt)
                    try await Task.sleep(nanoseconds: delay)
                    continue
                }
                
                return detail
            } catch {
                lastError = error
                if attempt >= maxAttempts {
                    throw error
                }
                
                let delay = retryDelay(for: attempt)
                try await Task.sleep(nanoseconds: delay)
            }
        }
        
        throw lastError ?? SessionLoggerError.invalidResponse
    }
    
    private func shouldRetry(detail: SessionDetailData, currentAttempt: Int, maxAttempts: Int) -> Bool {
        guard currentAttempt < maxAttempts else { return false }
        // If we already have either a summary or transcript turns, we can stop retrying
        if detail.summary != nil { return false }
        if !detail.turns.isEmpty { return false }
        // Retry a couple times while summary is still pending
        return detail.session.summaryStatus == .pending
    }
    
    private func retryDelay(for attempt: Int) -> UInt64 {
        // Exponential backoff starting at 0.5s: 0.5, 1.0, 2.0, 4.0
        let baseDelay: Double = 0.5
        let seconds = baseDelay * pow(2.0, Double(attempt - 1))
        return UInt64(seconds * 1_000_000_000)
    }
    
    private func fetchSessionSummary(sessionID: String) async throws -> SessionSummary? {
        guard let url = URL(string: "\(configuration.apiBaseURL)/sessions/\(sessionID)/summary") else {
            throw SessionLoggerError.invalidURL
        }
        
        let request = createAuthenticatedRequest(url: url, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        let decoder = createDecoder()
        
        do {
            return try handleResponse(data: data, response: response, decoder: decoder)
        } catch SessionLoggerError.serverError(let statusCode, _) where statusCode == 404 {
            return nil
        } catch SessionLoggerError.invalidResponse {
            return nil
        }
    }
    
    private func fetchSessionTurns(sessionID: String) async throws -> [Turn] {
        guard let url = URL(string: "\(configuration.apiBaseURL)/sessions/\(sessionID)/turns") else {
            throw SessionLoggerError.invalidURL
        }
        
        let request = createAuthenticatedRequest(url: url, method: "GET")
        let (data, response) = try await urlSession.data(for: request)
        let decoder = createDecoder()
        
        do {
            return try handleResponse(data: data, response: response, decoder: decoder)
        } catch SessionLoggerError.serverError(let statusCode, _) where statusCode == 404 {
            return []
        } catch SessionLoggerError.invalidResponse {
            return []
        }
    }

    func getUsageStats() async throws -> UsageStatsResponse {
        guard let url = URL(string: "\(configuration.apiBaseURL)/usage/stats") else {
            throw SessionLoggerError.invalidURL
        }

        let request = createAuthenticatedRequest(url: url, method: "GET")

        let (data, response) = try await urlSession.data(for: request)

        let decoder = createDecoder()
        return try handleResponse(data: data, response: response, decoder: decoder)
    }
    
    func deleteSession(sessionID: String) async throws {
        guard let url = URL(string: "\(configuration.apiBaseURL)/sessions/\(sessionID)") else {
            throw SessionLoggerError.invalidURL
        }
        
        let request = createAuthenticatedRequest(url: url, method: "DELETE")
        
        let (data, response) = try await urlSession.data(for: request)
        
        let decoder = createDecoder()
        let _: EmptyResponse = try handleResponse(data: data, response: response, decoder: decoder)
    }
    
    func deleteAllSessions() async throws {
        guard let url = URL(string: "\(configuration.apiBaseURL)/sessions") else {
            throw SessionLoggerError.invalidURL
        }
        
        let request = createAuthenticatedRequest(url: url, method: "DELETE")
        
        let (data, response) = try await urlSession.data(for: request)
        
        let decoder = createDecoder()
        let _: EmptyResponse = try handleResponse(data: data, response: response, decoder: decoder)
    }
}

// MARK: - Error Types

enum SessionLoggerError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case sessionNotFound
    case serverError(statusCode: Int, message: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Authentication required. Please log in again."
        case .sessionNotFound:
            return "Session not found on server. The database may have been cleared."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        }
    }
}

// MARK: - Response Types

struct EmptyResponse: Codable {}

struct UsageStatsResponse: Codable {
    let usedMinutes: Int
    let remainingMinutes: Int?
    let monthlyLimit: Int?
    let subscriptionTier: String
    let billingPeriodStart: Date
    let billingPeriodEnd: Date
}

struct SessionDetailData {
    let session: Session
    let summary: SessionSummary?
    let turns: [Turn]
}

private struct SessionDTO: Codable {
    let id: String?
    let userId: String?
    let context: String?
    let startedAt: String?
    let endedAt: String?
    let loggingEnabledSnapshot: Bool?
    let summaryStatus: String?
    let durationMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case context
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case loggingEnabledSnapshot = "logging_enabled_snapshot"
        case summaryStatus = "summary_status"
        case durationMinutes = "duration_minutes"
    }

    func toModel() -> Session {
        Session(
            id: id ?? "session-\(UUID().uuidString)",
            userId: userId ?? "unknown",
            context: Session.SessionContext(rawValue: context ?? "phone") ?? .phone,
            startedAt: parseDate(from: startedAt) ?? Date(),
            endedAt: parseDate(from: endedAt),
            loggingEnabledSnapshot: loggingEnabledSnapshot ?? false,
            summaryStatus: Session.SummaryStatus(rawValue: summaryStatus ?? "pending") ?? .pending,
            durationMinutes: durationMinutes
        )
    }
    
    private func parseDate(from string: String?) -> Date? {
        guard let string = string else { return nil }
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatterWithFractional.date(from: string) {
            return date
        }
        
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)
    }
}
