//
//  CallManagerTests.swift
//  AI Voice Copilot Tests
//

import XCTest
import CallKit
@testable import CarPlaySwiftUI

@MainActor
final class CallManagerTests: XCTestCase {
    var callManager: CallManager!
    var mockProvider: MockCXProvider!
    var mockCallController: MockCXCallController!
    var delegate: MockCallManagerDelegate!
    
    override func setUp() {
        super.setUp()
        
        // Create mock components
        let config = CXProviderConfiguration(localizedName: "Test")
        mockProvider = MockCXProvider(configuration: config)
        mockCallController = MockCXCallController()
        
        // Create CallManager with mocks
        callManager = CallManager(provider: mockProvider, callController: mockCallController)
        delegate = MockCallManagerDelegate()
        callManager.delegate = delegate
        
        // Set up mock to trigger delegate callbacks
        mockCallController.onRequest = { [weak self] transaction, completion in
            guard let self = self else { return }
            completion(nil) // Success
            
            // Simulate provider delegate callback
            if let startAction = transaction.actions.first as? CXStartCallAction {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.mockProvider.simulateStartCallAction(startAction, onCallManager: self.callManager)
                }
            } else if let endAction = transaction.actions.first as? CXEndCallAction {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.mockProvider.simulateEndCallAction(endAction, onCallManager: self.callManager)
                }
            }
        }
    }
    
    override func tearDown() {
        callManager.delegate = nil
        delegate = nil
        callManager = nil
        mockProvider = nil
        mockCallController = nil
        super.tearDown()
    }
    
    func testStartAssistantCall() {
        // Given
        let expectation = expectation(description: "Call started")
        delegate.onConnect = {
            expectation.fulfill()
        }
        
        // When
        callManager.startAssistantCall()
        
        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(delegate.didConnect)
        XCTAssertNotNil(mockCallController.lastTransaction)
    }
    
    func testEndCurrentCall() {
        // Given - start a call first
        let startExpectation = expectation(description: "Call started")
        delegate.onConnect = {
            startExpectation.fulfill()
        }
        callManager.startAssistantCall()
        wait(for: [startExpectation], timeout: 2.0)
        
        let endExpectation = expectation(description: "Call ended")
        delegate.onDisconnect = {
            endExpectation.fulfill()
        }
        
        // When
        callManager.endCurrentCall()
        
        // Then
        wait(for: [endExpectation], timeout: 2.0)
        XCTAssertTrue(delegate.didDisconnect)
    }
    
    func testCallFailure() {
        // Given
        mockCallController.shouldSucceed = false
        let expectation = expectation(description: "Call failed")
        delegate.onFail = { _ in
            expectation.fulfill()
        }
        
        // When
        callManager.startAssistantCall()
        
        // Then
        wait(for: [expectation], timeout: 2.0)
        XCTAssertTrue(delegate.didFail)
    }
}

class MockCallManagerDelegate: CallManagerDelegate {
    var didConnect = false
    var didDisconnect = false
    var didFail = false
    var lastError: Error?
    
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?
    var onFail: ((Error) -> Void)?
    
    func callManagerDidConnect() {
        didConnect = true
        onConnect?()
    }
    
    func callManagerDidDisconnect() {
        didDisconnect = true
        onDisconnect?()
    }
    
    func callManagerDidFail(error: Error) {
        didFail = true
        lastError = error
        onFail?(error)
    }
}

