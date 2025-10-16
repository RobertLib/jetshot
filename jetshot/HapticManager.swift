//
//  HapticManager.swift
//  jetshot
//
//  Created by Robert Libšanský on 20.10.2025.
//

import UIKit

class HapticManager {
    static let shared = HapticManager()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let notificationFeedback = UINotificationFeedbackGenerator()

    private init() {
        // Prepare generators for better performance
        lightImpact.prepare()
        mediumImpact.prepare()
        selectionFeedback.prepare()
    }

    /// Light haptic feedback for button touches and light interactions
    func lightTap() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
    }

    /// Medium haptic feedback for important actions
    func mediumTap() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
    }

    /// Heavy haptic feedback for significant events
    func heavyTap() {
        heavyImpact.impactOccurred()
        heavyImpact.prepare()
    }

    /// Selection feedback for navigating through options
    func selection() {
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    /// Success notification feedback
    func success() {
        notificationFeedback.notificationOccurred(.success)
        notificationFeedback.prepare()
    }

    /// Warning notification feedback
    func warning() {
        notificationFeedback.notificationOccurred(.warning)
        notificationFeedback.prepare()
    }

    /// Error notification feedback
    func error() {
        notificationFeedback.notificationOccurred(.error)
        notificationFeedback.prepare()
    }
}
