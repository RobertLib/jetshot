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

    /// Master switch for haptics, mirroring the existing sound/music toggles.
    /// Defaults to on when the user has never expressed a preference.
    var isHapticsEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: "isHapticsEnabled") != nil else {
                return true
            }
            return UserDefaults.standard.bool(forKey: "isHapticsEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isHapticsEnabled")
        }
    }

    private init() {
        // Prepare every generator, not just three of them
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        selectionFeedback.prepare()
        notificationFeedback.prepare()
    }

    /// Light haptic feedback for button touches and light interactions
    func lightTap() {
        guard isHapticsEnabled else { return }
        lightImpact.impactOccurred()
        lightImpact.prepare()
    }

    /// Medium haptic feedback for important actions
    func mediumTap() {
        guard isHapticsEnabled else { return }
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
    }

    /// Heavy haptic feedback for significant events
    func heavyTap() {
        guard isHapticsEnabled else { return }
        heavyImpact.impactOccurred()
        heavyImpact.prepare()
    }

    /// Selection feedback for navigating through options
    func selection() {
        guard isHapticsEnabled else { return }
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    /// Success notification feedback
    func success() {
        guard isHapticsEnabled else { return }
        notificationFeedback.notificationOccurred(.success)
        notificationFeedback.prepare()
    }

    /// Warning notification feedback
    func warning() {
        guard isHapticsEnabled else { return }
        notificationFeedback.notificationOccurred(.warning)
        notificationFeedback.prepare()
    }

    /// Error notification feedback
    func error() {
        guard isHapticsEnabled else { return }
        notificationFeedback.notificationOccurred(.error)
        notificationFeedback.prepare()
    }
}
