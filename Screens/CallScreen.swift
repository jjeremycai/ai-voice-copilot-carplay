//
//  CallScreen.swift
//  Shaw
//

import SwiftUI

struct CallScreen: View {
    @State private var callCoordinator = AssistantCallCoordinator.shared
    @State private var appCoordinator = AppCoordinator.shared
    @State private var settings = UserSettings.shared
    @State private var showErrorAlert = false
    @State private var selectedLoggingOption: LoggingOption?
    
    enum LoggingOption {
        case enabled
        case disabled
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if callCoordinator.callState == .idle {
                Form {
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
                    }

                    Section {
                        LoggingOptionsView(
                            selectedOption: $selectedLoggingOption,
                            settings: settings
                        )
                    } header: {
                        Text("Recording")
                    }
                }
            } else if callCoordinator.callState == .connected {
                VStack(spacing: 16) {
                    Spacer()

                    StatusIndicatorView(
                        isLoggingEnabled: selectedLoggingOption == .enabled
                    )
                    .padding(.horizontal, 24)

                    Spacer()
                }
            } else {
                Spacer()
            }

            if let errorMessage = callCoordinator.errorMessage {
                ErrorIndicatorView(message: errorMessage)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            callButton
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
        }
        .navigationTitle("Call")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if selectedLoggingOption == nil {
                selectedLoggingOption = settings.loggingEnabled ? .enabled : .disabled
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {
                callCoordinator.errorMessage = nil
            }
        } message: {
            if let errorMessage = callCoordinator.errorMessage {
                Text(errorMessage)
            }
        }
        .onChange(of: callCoordinator.errorMessage) { oldValue, newValue in
            showErrorAlert = newValue != nil
        }
    }

    private var callButton: some View {
        CallButtonView(
            selectedLoggingOption: selectedLoggingOption ?? .enabled
        )
    }
    
}

struct LoggingOptionsView: View {
    @Binding var selectedOption: CallScreen.LoggingOption?
    @Bindable var settings: UserSettings

    var body: some View {
        VStack(spacing: 12) {
            Button(action: {
                selectedOption = .enabled
                settings.loggingEnabled = true
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Save & Summarize")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Record conversation history and get AI-generated summaries")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if selectedOption == .enabled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Button(action: {
                selectedOption = .disabled
                settings.loggingEnabled = false
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Voice Only")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("No recording or history will be saved")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if selectedOption == .disabled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct CallButtonView: View {
    @State private var callCoordinator = AssistantCallCoordinator.shared
    let selectedLoggingOption: CallScreen.LoggingOption
    
    var body: some View {
        Button(action: {
            Task { @MainActor in
                if callCoordinator.callState == .idle {
                    let enableLogging = selectedLoggingOption == .enabled
                    await callCoordinator.startAssistantCall(context: "phone", enableLogging: enableLogging)
                } else {
                    callCoordinator.endAssistantCall()
                }
            }
        }) {
            HStack(spacing: 12) {
                if callCoordinator.callState == .connecting || callCoordinator.callState == .disconnecting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                } else {
                    Image(systemName: callCoordinator.callState == .idle ? "phone.fill" : "phone.down.fill")
                        .font(.system(size: 24, weight: .semibold))
                }
                
                Text(buttonText)
                    .font(.system(size: 20, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(buttonGradient)
            .cornerRadius(32)
            .shadow(color: buttonShadowColor.opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .disabled(callCoordinator.callState == .connecting || callCoordinator.callState == .disconnecting)
    }
    
    private var buttonText: String {
        switch callCoordinator.callState {
        case .idle:
            return "Start Call"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "End Call"
        case .disconnecting:
            return "Disconnecting..."
        }
    }
    
    private var buttonGradient: LinearGradient {
        switch callCoordinator.callState {
        case .idle:
            return LinearGradient(
                colors: [.blue, .blue.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .connecting, .disconnecting:
            return LinearGradient(
                colors: [.gray, .gray.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .connected:
            return LinearGradient(
                colors: [.red, .red.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
    
    private var buttonShadowColor: Color {
        switch callCoordinator.callState {
        case .idle:
            return .blue
        case .connecting, .disconnecting:
            return .gray
        case .connected:
            return .red
        }
    }
}

struct StatusIndicatorView: View {
    let isLoggingEnabled: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)
            
            Text(isLoggingEnabled ? "Recording and summarizing this call" : "Voice-only mode: No recording")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(20)
    }
}

struct ErrorIndicatorView: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(20)
    }
}

struct ModelPickerView: View {
    @Bindable var settings: UserSettings

    var body: some View {
        List {
            ForEach(AIModel.allCases, id: \.self) { model in
                Button {
                    settings.selectedModel = model
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.displayName)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(model.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if settings.selectedModel == model {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("AI Model")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct VoicePickerView: View {
    @Bindable var settings: UserSettings

    var body: some View {
        List {
            ForEach(TTSProvider.allCases, id: \.self) { provider in
                let voices = TTSVoice.voices(for: provider)
                Section(provider.displayName) {
                    ForEach(voices) { voice in
                        Button {
                            settings.selectedVoice = voice
                        } label: {
                            VoicePickerRow(voice: voice, isSelected: settings.selectedVoice.id == voice.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct VoicePickerRow: View {
    let voice: TTSVoice
    let isSelected: Bool
    @StateObject private var previewService = VoicePreviewService.shared
    @State private var isLoadingPreview = false
    @State private var previewError: String?

    private var isPlaying: Bool {
        previewService.isPlaying(for: voice)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(voice.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(voice.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isLoadingPreview {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button(action: {
                    Task {
                        await togglePreview()
                    }
                }) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .foregroundColor(isPlaying ? .red : .blue)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onChange(of: previewService.playingVoiceId) {
            // Update UI when playback state changes
        }
    }

    private func togglePreview() async {
        if isPlaying {
            previewService.stopPreview(for: voice)
        } else {
            previewService.stopAllPreviews()
            isLoadingPreview = true
            previewError = nil

            do {
                try await previewService.playPreview(for: voice)
            } catch {
                previewError = error.localizedDescription
                print("Failed to play preview: \(error)")
            }

            isLoadingPreview = false
        }
    }
}

#Preview {
    CallScreen()
}

// MARK: - Models

enum TTSProvider: String, Codable, CaseIterable {
    case cartesia
    case elevenlabs
    
    var displayName: String {
        switch self {
        case .cartesia: return "Cartesia"
        case .elevenlabs: return "ElevenLabs"
        }
    }
}

struct TTSVoice: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let provider: TTSProvider
    
    static let cartesiaVoices: [TTSVoice] = [
        TTSVoice(id: "cartesia-katie", name: "Katie", description: "Friendly female voice", provider: .cartesia),
        TTSVoice(id: "cartesia-kiefer", name: "Kiefer", description: "Professional male voice", provider: .cartesia),
        TTSVoice(id: "cartesia-kyle", name: "Kyle", description: "Casual male voice", provider: .cartesia),
        TTSVoice(id: "cartesia-tessa", name: "Tessa", description: "Warm female voice", provider: .cartesia)
    ]
    
    static let elevenlabsVoices: [TTSVoice] = [
        TTSVoice(id: "elevenlabs-rachel", name: "Rachel", description: "Clear female voice", provider: .elevenlabs),
        TTSVoice(id: "elevenlabs-clyde", name: "Clyde", description: "Deep male voice", provider: .elevenlabs),
        TTSVoice(id: "elevenlabs-roger", name: "Roger", description: "Mature male voice", provider: .elevenlabs),
        TTSVoice(id: "elevenlabs-sarah", name: "Sarah", description: "Young female voice", provider: .elevenlabs),
        TTSVoice(id: "elevenlabs-laura", name: "Laura", description: "Professional female voice", provider: .elevenlabs),
        TTSVoice(id: "elevenlabs-charlie", name: "Charlie", description: "Energetic male voice", provider: .elevenlabs)
    ]
    
    static func voices(for provider: TTSProvider) -> [TTSVoice] {
        switch provider {
        case .cartesia: return cartesiaVoices
        case .elevenlabs: return elevenlabsVoices
        }
    }
    
    static let `default` = cartesiaVoices[0]
}

enum AIModel: String, Codable, CaseIterable {
    case gpt4oMini = "gpt-4o-mini"
    case gpt4o = "gpt-4o"
    case gpt4Turbo = "gpt-4-turbo"
    
    var displayName: String {
        switch self {
        case .gpt4oMini: return "GPT-4o Mini"
        case .gpt4o: return "GPT-4o"
        case .gpt4Turbo: return "GPT-4 Turbo"
        }
    }
}
