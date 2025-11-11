//
//  CallManager.swift
//  AI Voice Copilot
//

import Foundation
import CallKit
import AVFoundation

protocol CallManagerDelegate: AnyObject {
    func callManagerDidConnect()
    func callManagerDidDisconnect()
    func callManagerDidFail(error: Error)
}

class CallManager: NSObject {
    private static var _shared: CallManager?
    static var shared: CallManager {
        if _shared == nil {
            _shared = CallManager()
        }
        return _shared!
    }
    
    // Allow resetting shared instance for testing
    static func resetShared() {
        _shared = nil
    }
    
    weak var delegate: CallManagerDelegate?
    
    private let provider: CXProviderProtocol
    private let callController: CXCallControllerProtocol
    private var currentCallUUID: UUID?
    
    // Dependency injection for testing
    init(provider: CXProviderProtocol? = nil, callController: CXCallControllerProtocol? = nil) {
        if let provider = provider, let callController = callController {
            // Test initialization
            self.provider = provider
            self.callController = callController
        } else {
            // Production initialization
            let configuration = CXProviderConfiguration()
            configuration.supportsVideo = false
            configuration.maximumCallsPerCallGroup = 1
            configuration.supportedHandleTypes = [.generic]
            configuration.iconTemplateImageData = nil
            
            self.provider = CXProvider(configuration: configuration)
            self.callController = CXCallController()
        }
        
        super.init()
        
        self.provider.setDelegate(self, queue: nil)
    }
    
    func startAssistantCall() {
        let handle = CXHandle(type: .generic, value: "AI Assistant")
        let startCallAction = CXStartCallAction(call: UUID(), handle: handle)
        startCallAction.isVideo = false
        
        let transaction = CXTransaction(action: startCallAction)
        
        callController.request(transaction) { [weak self] error in
            if let error = error {
                print("Error starting call: \(error)")
                self?.delegate?.callManagerDidFail(error: error)
            } else {
                self?.currentCallUUID = startCallAction.callUUID
            }
        }
    }
    
    func endCurrentCall() {
        guard let callUUID = currentCallUUID else { return }
        
        let endCallAction = CXEndCallAction(call: callUUID)
        let transaction = CXTransaction(action: endCallAction)
        
        callController.request(transaction) { error in
            if let error = error {
                print("Error ending call: \(error)")
            }
        }
    }
    
    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [
                    .allowBluetoothHFP,
                    .allowBluetoothA2DP,
                    .allowAirPlay,
                    .defaultToSpeaker
                ]
            )
            try audioSession.setActive(true)
            try audioSession.overrideOutputAudioPort(.speaker)
        } catch {
            print("Error configuring audio session: \(error)")
            delegate?.callManagerDidFail(error: error)
        }
    }
    
    private func deactivateAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Error deactivating audio session: \(error)")
        }
    }
}

extension CallManager: CXProviderDelegate {
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        configureAudioSession()
        action.fulfill()
        delegate?.callManagerDidConnect()
    }
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        deactivateAudioSession()
        action.fulfill()
        currentCallUUID = nil
        delegate?.callManagerDidDisconnect()
    }
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        action.fulfill()
    }
    
    func providerDidReset(_ provider: CXProvider) {
        currentCallUUID = nil
    }
}
