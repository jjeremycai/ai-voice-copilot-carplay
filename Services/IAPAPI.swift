//
//  IAPAPI.swift
//  Shaw
//

import Foundation

class IAPAPI {
    static let shared = IAPAPI()

    private let configuration = Configuration.shared
    private let authService = AuthService.shared
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func verify(transactionJWS: String) async throws -> VerifyResponse {
        guard let url = URL(string: "\(configuration.apiBaseURL)/iap/verify") else {
            throw IAPError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authService.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body = VerifyRequest(
            transactionJWS: transactionJWS,
            deviceId: authService.authToken ?? "",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            environment: getCurrentEnvironment()
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw IAPError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw IAPError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VerifyResponse.self, from: data)
    }

    private func getCurrentEnvironment() -> String {
        #if DEBUG
        return "Sandbox"
        #else
        return "Production"
        #endif
    }
}

struct VerifyRequest: Codable {
    let transactionJWS: String
    let deviceId: String
    let appVersion: String
    let environment: String
}

struct VerifyResponse: Codable {
    let isActive: Bool
    let isInGrace: Bool
    let productId: String?
    let originalTransactionId: String?
    let expiresAt: Date?
}

enum IAPError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        }
    }
}
