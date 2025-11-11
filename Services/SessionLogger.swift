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
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication token if available
        if let token = authService.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        return request
    }
    
    private func handleResponse<T: Decodable>(data: Data, response: URLResponse, decoder: JSONDecoder) throws -> T {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SessionLoggerError.invalidResponse
        }
        
        // Handle authentication errors
        if httpResponse.statusCode == 401 {
            throw SessionLoggerError.unauthorized
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Server error"
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
        guard let url = URL(string: "\(configuration.apiBaseURL)/sessions/start") else {
            throw SessionLoggerError.invalidURL
        }
        
        var request = createAuthenticatedRequest(url: url, method: "POST")
        
        let body: [String: Any] = [
            "context": context.rawValue
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await urlSession.data(for: request)
        
        let decoder = createDecoder()
        return try handleResponse(data: data, response: response, decoder: decoder)
    }
    
    func endSession(sessionID: String) async throws {
        guard let url = URL(string: "\(configuration.apiBaseURL)/sessions/end") else {
            throw SessionLoggerError.invalidURL
        }
        
        var request = createAuthenticatedRequest(url: url, method: "POST")
        
        let body: [String: Any] = [
            "session_id": sessionID
        ]
        
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
                guard let url = URL(string: "\(configuration.apiBaseURL)/sessions/\(sessionID)/turn") else { return }
                
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
    
    func fetchSessionDetail(sessionID: String) async throws -> (SessionSummary?, [Turn]) {
        guard let url = URL(string: "\(configuration.apiBaseURL)/sessions/\(sessionID)") else {
            throw SessionLoggerError.invalidURL
        }
        
        let request = createAuthenticatedRequest(url: url, method: "GET")
        
        let (data, response) = try await urlSession.data(for: request)
        
        let decoder = createDecoder()
        
        // Parse the actual response structure from backend
        struct SessionDetailResponse: Codable {
            let summary: SessionSummary?
            let turns: [Turn]
        }
        
        let detailResponse: SessionDetailResponse = try handleResponse(data: data, response: response, decoder: decoder)
        return (detailResponse.summary, detailResponse.turns)
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
    case serverError(statusCode: Int, message: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Authentication required. Please log in again."
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
