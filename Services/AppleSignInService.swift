//
//  AppleSignInService.swift
//  Shaw
//

import Foundation
import AuthenticationServices

@MainActor
class AppleSignInService: NSObject, ObservableObject {
    static let shared = AppleSignInService()

    @Published var isSignedIn = false
    @Published var userID: String?
    @Published var email: String?
    @Published var fullName: PersonNameComponents?

    private override init() {
        super.init()
        checkSignInStatus()
    }

    // MARK: - Sign In

    func signIn() async throws {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.email, .fullName]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    // MARK: - Sign Out

    func signOut() {
        userID = nil
        email = nil
        fullName = nil
        isSignedIn = false

        // Clear from UserDefaults
        UserDefaults.standard.removeObject(forKey: "appleUserID")
        UserDefaults.standard.removeObject(forKey: "appleEmail")
    }

    // MARK: - Check Status

    private func checkSignInStatus() {
        if let savedUserID = UserDefaults.standard.string(forKey: "appleUserID") {
            userID = savedUserID
            email = UserDefaults.standard.string(forKey: "appleEmail")

            // Verify credential is still valid
            let provider = ASAuthorizationAppleIDProvider()
            provider.getCredentialState(forUserID: savedUserID) { state, error in
                Task { @MainActor in
                    switch state {
                    case .authorized:
                        self.isSignedIn = true
                    case .revoked, .notFound:
                        self.signOut()
                    default:
                        break
                    }
                }
            }
        }
    }

    // MARK: - Save Credentials

    private func saveCredentials(userID: String, email: String?) {
        UserDefaults.standard.set(userID, forKey: "appleUserID")
        if let email = email {
            UserDefaults.standard.set(email, forKey: "appleEmail")
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }

        Task { @MainActor in
            userID = credential.user
            email = credential.email
            fullName = credential.fullName
            isSignedIn = true

            saveCredentials(userID: credential.user, email: credential.email)

            // Send to backend for user creation/login
            if let identityToken = credential.identityToken,
               let tokenString = String(data: identityToken, encoding: .utf8) {
                try? await AuthService.shared.signInWithApple(token: tokenString, userID: credential.user)
            }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("Sign in with Apple failed: \(error)")
    }
}
