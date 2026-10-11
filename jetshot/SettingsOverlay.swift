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
/// Drawn as a HUD readout rather than a dialog: dark glass inside lit corner brackets,
/// a tracked title with a hairline drawn out under it, and one row per switch with a
/// lamp that is lit when the channel is on.
///
/// Owns its own hit-testing: the host scene forwards every tap's location to
/// `handleTap(at:)` while the panel is up. Rows and the close button are found by
/// their geometry, not by asking the scene which named node is on top — that answer
/// depends on draw order, and with the scrim, the glass and the rows all under the
/// finger it is not one a modal should be built on.
final class SettingsOverlay: SKNode {

    static let nodeName = "settingsOverlay"

    private static let closeButtonName = "settingsCloseButton"

    /// Called after the overlay has finished animating out and removed itself.
    private var onDismiss: (() -> Void)?

    private var rows: [GameSetting: SKShapeNode] = [:]
    private var lamps: [GameSetting: SKShapeNode] = [:]
    private var lampGlows: [GameSetting: SKSpriteNode] = [:]
    private var stateLabels: [GameSetting: SKLabelNode] = [:]
    private var panelFrame: CGRect = .zero

    /// Guards against a second dismissal while the exit animation is still running.
    private var isDismissing = false

    /// How long after opening the panel ignores taps.
    ///
    /// It opens on a tap, right over the button that opened it: in the menu SETTINGS
    /// sits under CLOSE whenever ENDLESS is not unlocked, and in the pause menu it sits
    /// by the HAPTICS row and CLOSE. So the second tap of a double tap landed on a panel
    /// still scaling in, and closed it again or flipped a switch nobody had seen.
    static let openingGrace: CFTimeInterval = 0.25

    /// Real time rather than the host scene's clock: the pause menu hosts the panel over
    /// frozen gameplay.
    private let openedAt = CACurrentMediaTime()

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
        let scrim = SKSpriteNode(color: .black, size: CGSize(width: sceneSize.width + 4, height: sceneSize.height + 4))
        scrim.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        scrim.name = "settingsScrim"
        scrim.alpha = 0
        scrim.zPosition = -10
        addChild(scrim)
        scrim.run(SKAction.fadeAlpha(to: 0.78, duration: 0.2))
    }

    private func buildPanel(sceneSize: CGSize) {
        let accent = StoryPalette.cyan
        let rowHeight: CGFloat = 52
        let width = min(sceneSize.width / FilmUI.uiScale(for: sceneSize) - 48, 320)
        let rowsHeight = CGFloat(GameSetting.allCases.count) * rowHeight
        // Title block, the rows, the close button, and the air between them.
        let height = 30 + 30 + 26 + rowsHeight + 26 + UITheme.Dimensions.buttonHeightSecondary + 26

        let scale = FilmUI.uiScale(for: sceneSize)
        let centre = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        panelFrame = CGRect(x: centre.x - width * scale / 2, y: centre.y - height * scale / 2,
                            width: width * scale, height: height * scale)

        let panel = SKNode()
        panel.position = centre
        panel.name = "settingsPanel"
        panel.alpha = 0
        panel.setScale(scale * 0.96)
        addChild(panel)

        // Near opaque: over the pause menu, anything more and its lit type shows through.
        //
        // And a few steps below everything else on the panel. The view ignores sibling
        // order, and the lamps' glow and the title's bloom each hang one step *below*
        // the node they light — so with the glass on the same z as the rows, both drew
        // under 97% of it and the lit state had no halo at all.
        let glass = SKSpriteNode(color: FilmUI.glass, size: CGSize(width: width, height: height))
        glass.alpha = 0.97
        glass.zPosition = -3
        glass.name = "settingsGlass"
        panel.addChild(glass)

        let frame = SKShapeNode(rectOf: CGSize(width: width, height: height))
        frame.fillColor = .clear
        frame.strokeColor = accent.withAlphaComponent(0.16)
        frame.lineWidth = 1
        panel.addChild(frame)
        FilmUI.addBrackets(to: panel, size: CGSize(width: width, height: height), arm: 18, color: accent, width: 1.5)

        // Title, and the hairline that draws out under it.
        var y = height / 2 - 30 - 15
        let title = FilmUI.title(L10n.Settings.title, size: 26, color: UITheme.Colors.primaryCyanLight,
                                 glow: accent, tracking: 6, maxWidth: width - 40)
        title.position = CGPoint(x: 0, y: y)
        panel.addChild(title)

        y -= 15 + 14
        let rule = FilmUI.drawnRule(width: width - 48, color: accent, alpha: 0.45, delay: 0.1)
        rule.position = CGPoint(x: 0, y: y)
        panel.addChild(rule)

        // Rows, hung from just under the rule.
        y -= 12 + rowHeight / 2
        let rowWidth = width - 32
        for (index, setting) in GameSetting.allCases.enumerated() {
            let row = buildRow(setting, width: rowWidth, height: rowHeight)
            row.position = CGPoint(x: 0, y: y)
            panel.addChild(row)
            rows[setting] = row

            // A hairline between rows, so the list reads as a readout, not a form.
            if index < GameSetting.allCases.count - 1 {
                let divider = FilmUI.hairline(width: rowWidth, color: .white, alpha: 0.08)
                divider.position = CGPoint(x: 0, y: y - rowHeight / 2)
                panel.addChild(divider)
            }
            y -= rowHeight
        }

        let closeButton = UITheme.createButton(
            text: L10n.Settings.close,
            color: accent,
            width: UITheme.Dimensions.buttonWidthSmall,
            name: Self.closeButtonName
        )
        closeButton.position = CGPoint(x: 0, y: -height / 2 + 26 + UITheme.Dimensions.buttonHeightSecondary / 2)
        panel.addChild(closeButton)

        let open = SKAction.scale(to: scale, duration: 0.25)
        open.timingMode = .easeOut
        panel.run(.group([.fadeIn(withDuration: 0.2), open]))
    }

    /// One settings row: the channel's name on the left, its state on the right as a
    /// lamp and a word.
    ///
    /// The whole row is the hit target rather than just the lamp — a 52pt-tall strip is
    /// far easier to hit, and there is nothing else in it to tap by mistake.
    private func buildRow(_ setting: GameSetting, width: CGFloat, height: CGFloat) -> SKShapeNode {
        let row = SKShapeNode(rectOf: CGSize(width: width, height: height))
        row.fillColor = .clear
        row.strokeColor = .clear
        row.name = setting.nodeName

        let label = FilmUI.label(setting.title, size: 17, color: UITheme.Colors.textBody,
                                 tracking: 2.5, maxWidth: width - 120)
        label.horizontalAlignmentMode = .left
        label.position = CGPoint(x: -width / 2 + 8, y: 0)
        UITheme.centerOnCapBand(label)
        row.addChild(label)

        // The switch: a lamp in a small frame, and the state spelled out after it.
        let lampX = width / 2 - 74
        let lampGlow = NeonFX.radialGlow(radius: 14, color: StoryPalette.green)
        lampGlow.position = CGPoint(x: lampX, y: 0)
        lampGlow.zPosition = -1
        row.addChild(lampGlow)
        lampGlows[setting] = lampGlow

        let lamp = SKShapeNode(rectOf: CGSize(width: 9, height: 9))
        lamp.position = CGPoint(x: lampX, y: 0)
        lamp.lineWidth = 1
        row.addChild(lamp)
        lamps[setting] = lamp

        let state = SKLabelNode()
        state.horizontalAlignmentMode = .left
        state.verticalAlignmentMode = .center
        state.position = CGPoint(x: lampX + 14, y: 0)
        row.addChild(state)
        stateLabels[setting] = state

        let switchFrame = CGSize(width: 82, height: 28)
        let box = SKShapeNode(rectOf: switchFrame)
        box.position = CGPoint(x: width / 2 - switchFrame.width / 2 - 4, y: 0)
        box.fillColor = .clear
        box.strokeColor = UIColor.white.withAlphaComponent(0.12)
        box.lineWidth = 1
        box.name = "switchFrame"
        row.addChild(box)

        applyState(for: setting)
        return row
    }

    private func applyState(for setting: GameSetting) {
        guard let lamp = lamps[setting], let state = stateLabels[setting] else { return }

        let isOn = setting.isEnabled
        let tint = isOn ? StoryPalette.green : FilmUI.neutral

        lamp.fillColor = isOn ? tint : .clear
        lamp.strokeColor = tint.withAlphaComponent(isOn ? 1 : 0.6)
        lampGlows[setting]?.alpha = isOn ? 0.55 : 0
        FilmUI.set(state, isOn ? L10n.Settings.on : L10n.Settings.off,
                   font: UITheme.Typography.fontNumeric, size: 13,
                   color: isOn ? StoryPalette.mix(tint, .white, 0.3) : tint.withAlphaComponent(0.75),
                   tracking: 2)
    }

    // MARK: - Interaction

    /// Handles a tap at `location`, in the coordinates of the scene the overlay is in.
    /// Every tap is the overlay's while it is up: a row toggles, CLOSE or anywhere off
    /// the panel dismisses, and anything else on the panel is swallowed — as is every
    /// tap in the first `openingGrace` seconds.
    func handleTap(at location: CGPoint) {
        guard !isDismissing, CACurrentMediaTime() - openedAt >= Self.openingGrace,
              let scene = scene else { return }
        let point = scene.convert(location, to: self)

        for setting in GameSetting.allCases {
            guard let row = rows[setting], let box = row.path?.boundingBoxOfPath else { continue }
            if box.contains(scene.convert(location, to: row)) {
                toggle(setting)
                return
            }
        }

        if FilmUI.button(at: location, under: self, names: [Self.closeButtonName]) != nil {
            dismiss()
            return
        }

        if !panelFrame.contains(point) {
            dismiss()
        }
    }

    private func toggle(_ setting: GameSetting) {
        setting.isEnabled.toggle()
        applyState(for: setting)

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

        // The lamp blinks as it changes, so the row acknowledges the tap.
        if let lamp = lamps[setting] {
            lamp.removeAction(forKey: "press")
            lamp.run(.sequence([
                .scale(to: 1.5, duration: 0.06),
                .scale(to: 1.0, duration: 0.14)
            ]), withKey: "press")
        }
    }

    func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true

        if let close = FilmUI.descendant(of: self, named: Self.closeButtonName) {
            close.run(UITheme.createButtonPressAnimation {})
        }
        if let scene = scene {
            SoundManager.shared.playButtonClickSound(on: scene)
        }

        let completion = onDismiss
        onDismiss = nil

        // Completion block rather than an SKAction.run appended after
        // removeFromParent(): a node that has left the tree stops being updated, so
        // actions sequenced *after* its own removal never fire.
        run(SKAction.fadeOut(withDuration: 0.2)) { [weak self] in
            self?.removeFromParent()
            completion?()
        }
    }
}
