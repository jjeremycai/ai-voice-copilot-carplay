//
//  HapticFeedbackService.swift
//  Shaw
//

import UIKit

class HapticFeedbackService {
    static let shared = HapticFeedbackService()
    
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    private init() {
        // Prepare generators for immediate feedback
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        selectionFeedback.prepare()
        notificationFeedback.prepare()
    }
    
    func light() {
        lightImpact.impactOccurred()
    }
    
    func medium() {
        mediumImpact.impactOccurred()
    }
    
    func heavy() {
        heavyImpact.impactOccurred()
    }
    
    func selection() {
        selectionFeedback.selectionChanged()
    }
    
    func success() {
        notificationFeedback.notificationOccurred(.success)
    }
    
    func warning() {
        notificationFeedback.notificationOccurred(.warning)
    }
    
    func error() {
        notificationFeedback.notificationOccurred(.error)
    }
}

