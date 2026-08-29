//
//  SettingsOverlay.swift
//  jetshot
//

import SpriteKit

/// The three user-facing audio/feedback switches.
///
/// `SoundManager` and `HapticManager` have carried `isMusicEnabled`, `isSoundEnabled`
/// and `isHapticsEnabled` since early on, each persisted in UserDefaults and each
/// defaulting to on — but nothing outside those two files ever wrote to them. There was
/// no settings screen anywhere in the game, so a player had no way to silence 7 music
/// tracks and 45 sound effects, or to stop the haptics firing on every hit. This enum
/// is the bridge between those existing properties and the UI below.
enum GameSetting: CaseIterable {
    case music
    case sound
    case haptics

    var title: String {
        switch self {
        case .music: return L10n.Settings.music
        case .sound: return L10n.Settings.sound
        case .haptics: return L10n.Settings.haptics
        }
    }

    /// Node name for this row's tappable area.
    var nodeName: String {
        switch self {
        case .music: return "settingsRowMusic"
        case .sound: return "settingsRowSound"
        case .haptics: return "settingsRowHaptics"
        }
    }

    var isEnabled: Bool {
        get {
            switch self {
            case .music: return SoundManager.shared.isMusicEnabled
            case .sound: return SoundManager.shared.isSoundEnabled
            case .haptics: return HapticManager.shared.isHapticsEnabled
            }
        }
        nonmutating set {
            switch self {
            case .music: SoundManager.shared.isMusicEnabled = newValue
            case .sound: SoundManager.shared.isSoundEnabled = newValue
            case .haptics: HapticManager.shared.isHapticsEnabled = newValue
            }
        }
    }
}

/// Modal settings panel, presentable from any scene.
///
/// Owns its own hit-testing: the host scene forwards a tapped node name to
/// `handleTap(named:)` and gets back whether the overlay consumed it. That keeps the
/// scenes from having to know anything about the panel's internals, and matches the
/// name-based touch dispatch the rest of the game already uses.
final class SettingsOverlay: SKNode {

    static let nodeName = "settingsOverlay"

    private static let closeButtonName = "settingsCloseButton"

    /// Called after the overlay has finished animating out and removed itself.
    private var onDismiss: (() -> Void)?

    private var pillNodes: [GameSetting: SKShapeNode] = [:]
    private var pillLabels: [GameSetting: SKLabelNode] = [:]

    /// Guards against a second dismissal while the exit animation is still running.
    private var isDismissing = false

    // MARK: - Construction

    /// - Parameter sceneSize: used to size the full-screen scrim.
    init(sceneSize: CGSize, onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        super.init()

        name = Self.nodeName
        // Above the pause overlay (10000), so it works from the pause menu too.
        zPosition = 20000

        buildScrim(sceneSize: sceneSize)
        buildPanel(sceneSize: sceneSize)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildScrim(sceneSize: CGSize) {
        let scrim = SKShapeNode(rectOf: sceneSize)
        scrim.fillColor = UIColor.black.withAlphaComponent(0.7)
        scrim.strokeColor = .clear
        scrim.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        // Named so a tap on the backdrop closes the panel, matching the pause overlay.
        scrim.name = "settingsScrim"
        scrim.alpha = 0
        addChild(scrim)

        scrim.run(SKAction.fadeIn(withDuration: UITheme.Animations.durationQuick))
    }

    private func buildPanel(sceneSize: CGSize) {
        let rowHeight: CGFloat = 46
        let rowSpacing: CGFloat = 12
        let panelWidth = min(sceneSize.width - 60, 320)
        let rowsHeight = CGFloat(GameSetting.allCases.count) * rowHeight
            + CGFloat(GameSetting.allCases.count - 1) * rowSpacing
        let panelHeight = rowsHeight + 178

        let panel = SKShapeNode(
            rectOf: CGSize(width: panelWidth, height: panelHeight),
            cornerRadius: UITheme.Dimensions.cornerRadiusLarge
        )
        panel.fillColor = UIColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1.0)
        panel.strokeColor = UITheme.Colors.primaryCyan
        panel.lineWidth = UITheme.Dimensions.lineWidthThick
        panel.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        panel.setScale(0.8)
        panel.alpha = 0
        addChild(panel)

        GlowHelper.addEnhancedGlow(to: panel, color: UITheme.Colors.primaryCyan, intensity: 0.5)

        let title = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        title.text = L10n.Settings.title
        title.fontSize = UITheme.Typography.sizeMedium
        title.fontColor = UITheme.Colors.primaryCyanLight
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: panelHeight / 2 - 38)
        panel.addChild(title)

        // Rows, stacked from just under the title.
        let rowWidth = panelWidth - 44
        var rowY = panelHeight / 2 - 86 - rowHeight / 2

        for setting in GameSetting.allCases {
            let row = buildRow(setting, width: rowWidth, height: rowHeight)
            row.position = CGPoint(x: 0, y: rowY)
            panel.addChild(row)
            rowY -= rowHeight + rowSpacing
        }

        let closeButton = UITheme.createButton(
            text: L10n.Settings.close,
            color: UITheme.Colors.primaryCyan,
            width: 160,
            name: Self.closeButtonName,
            height: 44
        )
        closeButton.position = CGPoint(x: 0, y: -panelHeight / 2 + 46)
        panel.addChild(closeButton)

        panel.run(SKAction.group([
            SKAction.fadeIn(withDuration: UITheme.Animations.durationQuick),
            SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationQuick)
        ]))
    }

    /// One settings row: label on the left, ON/OFF pill on the right.
    ///
    /// The whole row is the hit target rather than just the pill — a 46pt-tall strip is
    /// far easier to hit than the pill alone, and there is nothing else in the row to
    /// tap by mistake.
    private func buildRow(_ setting: GameSetting, width: CGFloat, height: CGFloat) -> SKNode {
        let row = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: UITheme.Dimensions.cornerRadiusSmall)
        row.fillColor = UIColor(white: 1.0, alpha: 0.05)
        row.strokeColor = UIColor(white: 1.0, alpha: 0.12)
        row.lineWidth = 1
        row.name = setting.nodeName

        let label = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
        label.text = setting.title
        label.fontSize = UITheme.Typography.sizeSmall
        label.fontColor = UITheme.Colors.textLabel
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: -width / 2 + 16, y: 0)
        // Child labels must not swallow the row's identity: the host scene walks up
        // from the hit node to find a name, so giving these the row's name keeps the
        // lookup working wherever inside the row the tap lands.
        label.name = setting.nodeName
        row.addChild(label)

        let pillWidth: CGFloat = 62
        let pill = SKShapeNode(
            rectOf: CGSize(width: pillWidth, height: 26),
            cornerRadius: 13
        )
        pill.position = CGPoint(x: width / 2 - pillWidth / 2 - 12, y: 0)
        pill.name = setting.nodeName
        row.addChild(pill)
        pillNodes[setting] = pill

        let pillLabel = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        pillLabel.fontSize = 14
        pillLabel.horizontalAlignmentMode = .center
        pillLabel.verticalAlignmentMode = .center
        pillLabel.name = setting.nodeName
        pill.addChild(pillLabel)
        pillLabels[setting] = pillLabel

        applyPillStyle(for: setting)

        return row
    }

    private func applyPillStyle(for setting: GameSetting) {
        guard let pill = pillNodes[setting], let label = pillLabels[setting] else { return }

        let isOn = setting.isEnabled
        let tint = isOn ? UITheme.Colors.successGreenLight : UITheme.Colors.textLabelInactive

        pill.fillColor = tint.withAlphaComponent(isOn ? 0.22 : 0.12)
        pill.strokeColor = tint
        pill.lineWidth = UITheme.Dimensions.lineWidthThin
        label.text = isOn ? L10n.Settings.on : L10n.Settings.off
        label.fontColor = tint
    }

    // MARK: - Interaction

    /// Handles a tap on `nodeName`.
    /// - Returns: `true` if the overlay consumed the tap, so the host scene can stop.
    @discardableResult
    func handleTap(named nodeName: String?) -> Bool {
        guard let nodeName = nodeName else {
            // A tap that hit no named node still landed on the modal scrim, so swallow
            // it rather than letting it reach the scene underneath.
            return true
        }

        if let setting = GameSetting.allCases.first(where: { $0.nodeName == nodeName }) {
            toggle(setting)
            return true
        }

        if nodeName == Self.closeButtonName || nodeName == "settingsScrim" {
            dismiss()
            return true
        }

        // Anything else was inside the panel but not interactive — still ours.
        return true
    }

    private func toggle(_ setting: GameSetting) {
        setting.isEnabled.toggle()
        applyPillStyle(for: setting)

        // Feedback has to come *after* the flip so the player hears/feels the state
        // they just switched into — and so turning a channel off doesn't then play a
        // sound through it.
        if setting.isEnabled {
            switch setting {
            case .haptics: HapticManager.shared.mediumTap()
            case .sound, .music: break
            }
        }
        if let scene = scene {
            SoundManager.shared.playButtonClickSound(on: scene)
        }

        // A brief press on the pill, so the row acknowledges the tap.
        if let pill = pillNodes[setting] {
            pill.removeAction(forKey: "pillPress")
            pill.run(SKAction.sequence([
                SKAction.scale(to: 1.12, duration: UITheme.Animations.durationFast),
                SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationFast)
            ]), withKey: "pillPress")
        }
    }

    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true

        let completion = onDismiss
        onDismiss = nil

        // Completion block rather than an SKAction.run appended after
        // removeFromParent(): a node that has left the tree stops being updated, so
        // actions sequenced *after* its own removal never fire.
        run(SKAction.fadeOut(withDuration: UITheme.Animations.durationQuick)) { [weak self] in
            self?.removeFromParent()
            completion?()
        }
    }
}
