//
//  StoryScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.01.2026.
//

import SpriteKit

enum StoryType {
    case opening
    case ending
}

/// The opening and ending cinematics.
///
/// These used to be a text crawl over the menu starfield. They are now short films:
/// a sequence of `StoryShot`s rendered in real time by `WireCanvas`, cut together
/// through black or white, letterboxed, with the story's paragraphs as subtitles
/// timed to the picture. The shots themselves live in `StoryOpening.swift` and
/// `StoryEnding.swift`; this type is the projectionist — it lays out the frame,
/// runs the clock, cuts between shots, sets the captions and handles the exit.
class StoryScene: SKScene {

    private let storyType: StoryType
    private let targetLevel: Int?

    private var shots: [StoryShot] = []
    private var timelines: [ShotTimeline] = []
    private var shotIndex = 0
    private var shotTime: Float = 0
    private var previousShotTime: Float = -1
    private var totalTime: Float = 0
    private var lastUpdateTime: TimeInterval?
    private var isSkipped = false
    private var isBuilt = false

    private var canvas: WireCanvas!
    private var overlay: StoryOverlay!
    private let captionLayer = SKNode()
    private var captions: [Int: SKLabelNode] = [:]
    private var shutter: SKSpriteNode!
    private var flash: SKSpriteNode!
    private var topBar: SKSpriteNode!
    private var bottomBar: SKSpriteNode!
    private var frameFurniture = SKNode()
    private var timecodeLabel: SKLabelNode!
    private var chapterLabel: SKLabelNode!
    private var recordDot: SKShapeNode!
    private var skipLabel: SKLabelNode!

    private var filmFrame: CGRect = .zero
    private var barHeight: CGFloat = 0
    private var safeAreaBottom: CGFloat = 0
    /// Type grows a little on wide screens so captions keep their weight on an iPad.
    private var typeScale: CGFloat = 1

    /// Length of the frame being drawn, for the decays below.
    private var frameDelta: Float = 0
    private var cueFlash: Float = 0
    private var cueShake: Float = 0
    private var cueShakeDecay: Float = 1

    // Touch tracking for tap vs swipe detection
    private var touchStartLocation: CGPoint?
    private var touchStartTime: TimeInterval = 0

    #if DEBUG
    /// Shot to start on, for previewing one clip without sitting through the rest.
    /// Set by `DebugLaunch` from `-shot`.
    var debugStartShot = 0
    /// Seconds into that shot, from `-at`. The film holds still there, so the
    /// simulator can be screenshotted on an exact frame.
    var debugStartTime: Float = 0
    private var debugHold: Bool { debugStartTime > 0 }
    #endif

    init(size: CGSize, type: StoryType, targetLevel: Int? = nil) {
        self.storyType = type
        self.targetLevel = targetLevel
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The shots of a film, in order. Exposed for the tests.
    static func shots(for type: StoryType) -> [StoryShot] {
        switch type {
        case .opening: return StoryOpening.shots()
        case .ending: return StoryEnding.shots()
        }
    }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.005, green: 0.006, blue: 0.02, alpha: 1)
        safeAreaBottom = GameConfiguration.safeAreaBottom(in: view)

        shots = Self.shots(for: storyType)
        timelines = shots.map(ShotTimeline.init)

        build(safeTop: GameConfiguration.safeAreaTop(in: view))
        isBuilt = true

        #if DEBUG
        shotIndex = min(max(0, debugStartShot), shots.count - 1)
        #endif
        enterShot(shotIndex)
        #if DEBUG
        if debugHold {
            totalTime = 2
            previousShotTime = debugStartTime - 0.05
            shotTime = debugStartTime
        }
        #endif
        render()

        SoundManager.shared.playSpecificMusic(named: SoundManager.storyMusicTrack)
    }

    override func willMove(from view: SKView) {
        removeAllActions()
        removeAllChildren()
        captions.removeAll()
    }

    override func update(_ currentTime: TimeInterval) {
        guard isBuilt, !isSkipped else { return }
        // Clamped so a hitch (or the first frame after a backgrounding) does not
        // jump the film forward by seconds and skip a cut.
        let dt = Float(lastUpdateTime.map { min(1.0 / 20, max(0, currentTime - $0)) } ?? 0)
        lastUpdateTime = currentTime
        #if DEBUG
        if debugHold {
            // Re-render the same instant, so captions and HUD settle onto the frame.
            previousShotTime = shotTime
            frameDelta = dt
            render()
            return
        }
        #endif
        advance(by: dt)
    }

    // MARK: - Layout

    private func build(safeTop: CGFloat) {
        typeScale = min(1.45, max(1, size.width / 430))

        // Bars deep enough to carry four lines of caption beneath the picture, and
        // never less than a sixth of the screen, which is what makes it read as
        // widescreen rather than as a dark margin.
        barHeight = max(safeTop + 64, safeAreaBottom + 150 * typeScale, size.height * 0.16).rounded()
        filmFrame = CGRect(x: 0, y: barHeight, width: size.width, height: size.height - barHeight * 2)

        canvas = WireCanvas(viewport: filmFrame)
        canvas.zPosition = 0
        addChild(canvas)

        overlay = StoryOverlay(canvas: canvas, frame: filmFrame, typeScale: typeScale)
        overlay.node.zPosition = 50
        addChild(overlay.node)

        // Vignette over the picture, so the frame falls away into the bars.
        let grade = NeonFX.gradeOverlay(size: size)
        grade.zPosition = 40
        addChild(grade)

        captionLayer.zPosition = 120
        addChild(captionLayer)

        shutter = SKSpriteNode(color: .black, size: CGSize(width: size.width + 4, height: size.height + 4))
        shutter.position = CGPoint(x: size.width / 2, y: size.height / 2)
        shutter.zPosition = 80
        addChild(shutter)

        flash = SKSpriteNode(color: .white, size: filmFrame.size)
        flash.position = CGPoint(x: filmFrame.midX, y: filmFrame.midY)
        flash.zPosition = 85
        flash.alpha = 0
        flash.blendMode = .add
        addChild(flash)

        topBar = SKSpriteNode(color: .black, size: CGSize(width: size.width, height: barHeight))
        topBar.anchorPoint = CGPoint(x: 0.5, y: 0)
        topBar.position = CGPoint(x: size.width / 2, y: size.height)
        topBar.zPosition = 100
        addChild(topBar)

        bottomBar = SKSpriteNode(color: .black, size: CGSize(width: size.width, height: barHeight))
        bottomBar.anchorPoint = CGPoint(x: 0.5, y: 1)
        bottomBar.position = CGPoint(x: size.width / 2, y: 0)
        bottomBar.zPosition = 100
        addChild(bottomBar)

        buildFrameFurniture()
        setupSkipLabel()
    }

    /// Viewfinder corners, a running timecode and the shot counter.
    private func buildFrameFurniture() {
        frameFurniture.zPosition = 110
        frameFurniture.alpha = 0
        addChild(frameFurniture)

        let inset: CGFloat = 12, arm: CGFloat = 16
        let path = CGMutablePath()
        let r = filmFrame.insetBy(dx: inset, dy: inset)
        for (corner, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1, 1), (CGPoint(x: r.maxX, y: r.minY), -1, 1),
                                 (CGPoint(x: r.minX, y: r.maxY), 1, -1), (CGPoint(x: r.maxX, y: r.maxY), -1, -1)]
            as [(CGPoint, CGFloat, CGFloat)] {
            path.move(to: CGPoint(x: corner.x + arm * dx, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + arm * dy))
        }
        let corners = SKShapeNode(path: path)
        corners.strokeColor = StoryPalette.cyan.withAlphaComponent(0.35)
        corners.lineWidth = 1
        frameFurniture.addChild(corners)

        let y = filmFrame.maxY + 10
        recordDot = SKShapeNode(circleOfRadius: 3)
        recordDot.fillColor = StoryPalette.red
        recordDot.strokeColor = .clear
        recordDot.position = CGPoint(x: inset + 3, y: y + 4)
        frameFurniture.addChild(recordDot)

        timecodeLabel = SKLabelNode(fontNamed: UITheme.Typography.fontNumeric)
        timecodeLabel.fontSize = 10 * typeScale
        timecodeLabel.fontColor = UITheme.Colors.textSecondary.withAlphaComponent(0.6)
        timecodeLabel.horizontalAlignmentMode = .left
        timecodeLabel.verticalAlignmentMode = .baseline
        timecodeLabel.position = CGPoint(x: inset + 12, y: y)
        frameFurniture.addChild(timecodeLabel)

        chapterLabel = SKLabelNode(fontNamed: UITheme.Typography.fontNumeric)
        chapterLabel.fontSize = 10 * typeScale
        chapterLabel.fontColor = UITheme.Colors.textSecondary.withAlphaComponent(0.6)
        chapterLabel.horizontalAlignmentMode = .right
        chapterLabel.verticalAlignmentMode = .baseline
        chapterLabel.position = CGPoint(x: size.width - inset, y: y)
        frameFurniture.addChild(chapterLabel)
    }

    private func setupSkipLabel() {
        skipLabel = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
        skipLabel.text = L10n.Story.skipHint
        skipLabel.fontSize = 13 * typeScale
        skipLabel.fontColor = UITheme.Colors.textSecondary
        skipLabel.position = CGPoint(x: size.width / 2, y: safeAreaBottom + 14)
        skipLabel.alpha = 0
        skipLabel.zPosition = 130
        addChild(skipLabel)

        skipLabel.run(SKAction.sequence([
            SKAction.wait(forDuration: 2.5),
            SKAction.fadeAlpha(to: 0.4, duration: 1.0)
        ]))
    }

    // MARK: - Clock

    private func advance(by dt: Float) {
        frameDelta = dt
        previousShotTime = shotTime
        shotTime += dt
        totalTime += dt

        while shotTime >= timelines[shotIndex].duration {
            shotTime -= timelines[shotIndex].duration
            if shotIndex + 1 >= shots.count {
                storyComplete(fadeDuration: 0.8)
                return
            }
            shotIndex += 1
            enterShot(shotIndex)
            previousShotTime = -1
        }
        render()
    }

    private func enterShot(_ index: Int) {
        for (_, label) in captions { label.removeFromParent() }
        captions.removeAll()
        overlay.reset()
        chapterLabel?.text = String(format: "%02d / %02d", index + 1, shots.count)
        if shots[index].entry == .flash { cueFlash = max(cueFlash, 1) }
    }

    private func render() {
        let shot = shots[shotIndex]
        let timeline = timelines[shotIndex]
        let frame = ShotFrame(
            t: shotTime, previousT: previousShotTime, duration: timeline.duration,
            canvas: canvas, overlay: overlay, timeline: timeline
        )

        for (at, cue) in shot.cues where frame.crossed(at * timeline.duration) {
            overlay.queue(cue)
        }

        canvas.settings = WireCanvas.Settings()
        overlay.frameShake = 0
        canvas.shake = shakeOffset()
        shot.render(frame)
        canvas.end()

        runCues()
        updateTransitions(timeline: timeline)
        updateCaptions(timeline: timeline)
        updateFurniture()
    }

    private func shakeOffset() -> CGPoint {
        let amount = max(cueShake, overlay?.frameShake ?? 0)
        guard amount > 0.05 else { return .zero }
        let t = totalTime
        // Two incommensurate frequencies per axis: reads as a jolt, not a wobble.
        return CGPoint(x: CGFloat(amount * (sin(t * 71) * 0.6 + sin(t * 43 + 1) * 0.4)),
                       y: CGFloat(amount * (sin(t * 59 + 2) * 0.6 + sin(t * 37) * 0.4)))
    }

    private func runCues() {
        for cue in overlay.drainCues() {
            switch cue {
            case .sound(let sound): play(sound)
            case .haptic(let haptic): buzz(haptic)
            case .flash(let peak): cueFlash = max(cueFlash, peak)
            case .shake(let amount, let duration):
                cueShake = max(cueShake, amount)
                cueShakeDecay = amount / Float(max(0.05, duration))
            }
        }
    }

    private func play(_ sound: StorySound) {
        let audio = SoundManager.shared
        switch sound {
        case .ignition: audio.playLevelStartSound(on: self)
        case .rift: audio.playTeleportSound(on: self)
        case .entities: audio.playBossAppearSound(on: self)
        case .bigBang: audio.playBossDefeatSound(on: self)
        case .blast: audio.playExplosionSound(on: self)
        case .charge: audio.playShieldActivateSound(on: self)
        case .energy: audio.playPowerUpSound(on: self)
        case .arc: audio.playLightningSound(on: self)
        }
    }

    private func buzz(_ haptic: StoryHaptic) {
        let haptics = HapticManager.shared
        switch haptic {
        case .light: haptics.lightTap()
        case .medium: haptics.mediumTap()
        case .heavy: haptics.heavyTap()
        case .tick: haptics.selection()
        case .success: haptics.success()
        }
    }

    /// Fades through black or white at the cuts, and the flash and shake cues.
    private func updateTransitions(timeline: ShotTimeline) {
        let shot = shots[shotIndex]
        let t = shotTime, d = timeline.duration
        var black: Float = 0

        // Way in.
        if shotIndex == 0 && totalTime <= t + 0.001 {
            black = 1 - smooth(0.2, 1.6, t)
        } else if shot.entry == .fade {
            black = 1 - smooth(0, 0.6, t)
        }

        // Way out, decided by how the next shot enters.
        if shotIndex + 1 < shots.count {
            switch shots[shotIndex + 1].entry {
            case .fade: black = max(black, smooth(d - 0.5, d, t))
            case .flash: cueFlash = max(cueFlash, smooth(d - 0.35, d, t) * 0.85)
            case .cut: break
            }
        } else {
            black = max(black, smooth(d - 0.9, d, t))
        }
        shutter.alpha = CGFloat(black)

        flash.alpha = CGFloat(min(1, cueFlash))
        cueFlash = max(0, cueFlash - frameDelta * 2.2)
        cueShake = max(0, cueShake - cueShakeDecay * frameDelta)

        // Letterbox closes in over the opening seconds.
        let bars = easeOut(min(1, totalTime / 1.4))
        topBar.position.y = size.height - CGFloat(bars) * barHeight
        bottomBar.position.y = CGFloat(bars) * barHeight
    }

    private func updateFurniture() {
        frameFurniture.alpha = CGFloat(smooth(1.0, 2.2, totalTime)) * 0.9
        let frames = Int(totalTime * 24)
        timecodeLabel.text = String(format: "%02d:%02d:%02d", frames / 1440, (frames / 24) % 60, frames % 24)
        recordDot.alpha = sin(totalTime * 4) > -0.2 ? 1 : 0.15
    }

    // MARK: - Captions

    private func updateCaptions(timeline: ShotTimeline) {
        let t = shotTime
        for (index, beat) in timeline.beats.enumerated() {
            let fadeIn: Float = beat.style == .title ? 1.0 : 0.45
            let fadeOut: Float = beat.style == .subtitle ? 0.35 : 0.6
            guard t >= beat.start, t <= beat.end else {
                if let label = captions.removeValue(forKey: index) { label.removeFromParent() }
                continue
            }
            let label = captions[index] ?? makeCaption(beat, key: index)
            let local = t - beat.start
            let life = beat.end - beat.start
            let alpha = smooth(0, fadeIn, local) * (1 - smooth(life - fadeOut, life, local))
            label.alpha = CGFloat(alpha)
            let rise = (1 - easeOut(local / fadeIn)) * 8
            let base = label.userData?["y"] as? CGFloat ?? label.position.y
            switch beat.style {
            case .subtitle:
                label.position.y = base - CGFloat(rise)
            case .card, .cardHigh, .title:
                // A slow push, the way a title card settles on screen.
                label.setScale(CGFloat(1.06 - 0.06 * easeOut(local / life)))
            }
        }
    }

    private func makeCaption(_ beat: ShotTimeline.Beat, key: Int) -> SKLabelNode {
        let label = SKLabelNode()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.horizontalAlignmentMode = .center
        let width = min(filmFrame.width - 48, 560 * typeScale)
        label.preferredMaxLayoutWidth = width

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2

        func styled(_ font: String, _ size: CGFloat, _ color: UIColor, _ kern: CGFloat) -> NSAttributedString {
            NSAttributedString(string: beat.text, attributes: [
                .font: UIFont(name: font, size: size) ?? UIFont.systemFont(ofSize: size, weight: .bold),
                .foregroundColor: color,
                .kern: kern,
                .paragraphStyle: paragraph
            ])
        }

        switch beat.style {
        case .subtitle:
            // Hangs from just under the picture, shrinking to fit the bar rather than
            // ever spilling into the skip hint.
            label.verticalAlignmentMode = .top
            let room = barHeight - 18 - (safeAreaBottom + 34)
            var fontSize = 19 * typeScale
            repeat {
                label.attributedText = styled(UITheme.Typography.fontRegular, fontSize,
                                              UIColor(white: 0.93, alpha: 1), 0.3)
                fontSize -= 1
            } while label.frame.height > room && fontSize > 12
            label.position = CGPoint(x: size.width / 2, y: barHeight - 18)

        case .card, .cardHigh:
            label.verticalAlignmentMode = .center
            label.attributedText = styled(UITheme.Typography.fontBold, 30 * typeScale, .white, 1.2)
            let y = beat.style == .card ? filmFrame.midY : filmFrame.minY + filmFrame.height * 0.76
            label.position = CGPoint(x: size.width / 2, y: y)
            StoryOverlay.addBloom(to: label, glow: styled(UITheme.Typography.fontBold, 30 * typeScale, StoryPalette.cyan, 1.2),
                                  blur: 14, intensity: 0.6)

        case .title:
            label.verticalAlignmentMode = .center
            // One line if it can be had: a title broken over two reads as a caption.
            var fontSize = 46 * typeScale
            var gold = styled(UITheme.Typography.fontBold, fontSize, UITheme.Colors.primaryGold, fontSize * 0.2)
            while gold.size().width > width && fontSize > 30 * typeScale {
                fontSize -= 2
                gold = styled(UITheme.Typography.fontBold, fontSize, UITheme.Colors.primaryGold, fontSize * 0.2)
            }
            label.attributedText = gold
            label.position = CGPoint(x: size.width / 2, y: filmFrame.midY)
            StoryOverlay.addBloom(to: label, glow: gold, blur: 18, intensity: 0.9)
            // A hairline that draws out under the title.
            let rule = SKSpriteNode(color: UITheme.Colors.primaryGold, size: CGSize(width: min(width, 260 * typeScale), height: 1))
            rule.position = CGPoint(x: 0, y: -label.frame.height / 2 - 14)
            rule.xScale = 0.01
            rule.blendMode = .add
            rule.run(SKAction.sequence([.wait(forDuration: 0.4), .scaleX(to: 1, duration: 1.4)]))
            label.addChild(rule)
        }

        label.userData = ["y": label.position.y]
        label.alpha = 0
        captionLayer.addChild(label)
        captions[key] = label
        return label
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isSkipped, let touch = touches.first else { return }

        touchStartLocation = touch.location(in: self)
        touchStartTime = touch.timestamp
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isSkipped, let touch = touches.first, let startLocation = touchStartLocation else { return }

        let endLocation = touch.location(in: self)
        let distance = hypot(endLocation.x - startLocation.x, endLocation.y - startLocation.y)
        let duration = touch.timestamp - touchStartTime

        // Only skip if it's a tap (small movement, short duration)
        if distance < 20 && duration < 0.3 {
            // Not `playButtonClickSound(on: self)`: this scene is presenting the next one
            // in the same breath, and the click queued on it never got to play.
            SoundManager.shared.playSceneExitClickSound()
            storyComplete(fadeDuration: 1.0)
        }

        touchStartLocation = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStartLocation = nil
    }

    // MARK: - Exit

    private func storyComplete(fadeDuration: TimeInterval) {
        guard !isSkipped else { return }
        isSkipped = true

        // Fade the story music out with the picture and hand back to the level rotation,
        // which the next screen picks up as it arrives. This used to stop and "restart"
        // the music, which only restarted the story track from the top.
        SoundManager.shared.endSpecificMusic(fadeDuration: fadeDuration)

        skipLabel?.removeAllActions()

        let transition = SKTransition.fade(withDuration: fadeDuration)

        guard let view = view else { return }

        switch storyType {
        case .opening:
            // Record that the intro has been seen, so replaying level 1 goes straight
            // into the game. This is the single exit point for both the natural end of
            // the film and the tap-to-skip, so it covers both.
            LevelManager.shared.hasSeenOpeningStory = true

            // Start the game
            if let level = targetLevel {
                let gameScene = GameScene(size: view.bounds.size)
                gameScene.scaleMode = .resizeFill
                gameScene.currentLevel = level

                // For level 1, always start with default weapons
                // For other levels (if story can be shown), load from previous level
                if level > 1 {
                    let weapons = LevelManager.shared.getLevelWeapons(level: level - 1)
                    gameScene.startingBulletCount = weapons.bulletCount
                    gameScene.startingSideMissileCount = weapons.sideMissileCount
                }

                view.presentScene(gameScene, transition: transition)
            } else {
                let menu = MenuScene(size: view.bounds.size)
                menu.scaleMode = .resizeFill
                view.presentScene(menu, transition: transition)
            }
        case .ending:
            // Hand off to the victory screen, which owns the total score and the
            // play-again / levels / menu choices.
            let completionScene = GameCompletionScene(
                size: view.bounds.size,
                totalScore: LevelManager.shared.getTotalScore()
            )
            completionScene.scaleMode = .resizeFill
            view.presentScene(completionScene, transition: transition)
        }
    }
}

// MARK: - Overlay

/// The HUD layer over the picture: typed labels and target brackets that shots
/// pin to projected 3D points, plus the cue queue shots post into.
final class StoryOverlay {
    let node = SKNode()
    let frame: CGRect
    let typeScale: CGFloat
    /// The strongest continuous shake any draw asked for this frame.
    var frameShake: Float = 0

    private unowned let canvas: WireCanvas
    private var labels: [String: SKLabelNode] = [:]
    private var shownText: [String: String] = [:]
    private var pending: [StoryCue] = []

    init(canvas: WireCanvas, frame: CGRect, typeScale: CGFloat) {
        self.canvas = canvas
        self.frame = frame
        self.typeScale = typeScale
    }

    func reset() {
        node.removeAllChildren()
        labels.removeAll()
        shownText.removeAll()
    }

    func queue(_ cue: StoryCue) { pending.append(cue) }

    func drainCues() -> [StoryCue] {
        defer { pending.removeAll() }
        return pending
    }

    /// A label that types itself out as `reveal` goes from 0 to 1, with a block
    /// cursor while it is typing.
    func tag(_ key: String, _ text: String, at point: CGPoint, size: CGFloat = 12,
             color: UIColor = StoryPalette.cyan, reveal: Float = 1, alpha: Float = 1,
             align: SKLabelHorizontalAlignmentMode = .left, mono: Bool = true, tracking: CGFloat = 2,
             blink: Float = 0) {
        let label: SKLabelNode
        if let existing = labels[key] {
            label = existing
        } else {
            label = SKLabelNode()
            label.verticalAlignmentMode = .center
            label.blendMode = .add
            node.addChild(label)
            labels[key] = label
        }
        label.horizontalAlignmentMode = align

        let count = Int(Float(text.count) * clamp01(reveal))
        let typing = reveal > 0 && reveal < 1
        let cursorOn = typing && Int(blink * 8) % 2 == 0
        let shown = String(text.prefix(count)) + (cursorOn ? "▌" : (typing ? " " : ""))
        if shownText[key] != shown {
            shownText[key] = shown
            let font = mono ? UITheme.Typography.fontNumeric : UITheme.Typography.fontBold
            let pointSize = size * typeScale
            label.attributedText = NSAttributedString(string: shown, attributes: [
                .font: UIFont(name: font, size: pointSize) ?? UIFont.monospacedSystemFont(ofSize: pointSize, weight: .bold),
                .foregroundColor: color,
                .kern: tracking
            ])
        }
        label.position = point
        label.alpha = CGFloat(clamp01(alpha))
    }

    /// Display lettering with a real blurred bloom behind it. Built once per key.
    func title(_ key: String, _ text: String, at point: CGPoint, size: CGFloat, color: UIColor,
               glow: UIColor, alpha: Float, tracking: CGFloat = 10, scale: CGFloat = 1) {
        let label: SKLabelNode
        if let existing = labels[key] {
            label = existing
        } else {
            func lettering(_ color: UIColor) -> NSAttributedString {
                let pointSize = size * typeScale
                return NSAttributedString(string: text, attributes: [
                    .font: UIFont(name: UITheme.Typography.fontBold, size: pointSize) ?? UIFont.systemFont(ofSize: pointSize, weight: .heavy),
                    .foregroundColor: color,
                    .kern: tracking
                ])
            }
            label = SKLabelNode()
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.attributedText = lettering(color)
            Self.addBloom(to: label, glow: lettering(glow), blur: 16, intensity: 1)
            node.addChild(label)
            labels[key] = label
        }
        label.position = point
        label.alpha = CGFloat(clamp01(alpha))
        label.setScale(scale)
    }

    /// Puts a blurred copy of `label` behind it, set in `glow`.
    ///
    /// `NeonFX.addTextBloom` copies a label's plain text, which loses the tracking,
    /// the wrapping and the colour of an attributed, multi-line caption.
    static func addBloom(to label: SKLabelNode, glow: NSAttributedString, blur: CGFloat, intensity: CGFloat) {
        let effect = SKEffectNode()
        effect.shouldRasterize = true
        effect.filter = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: blur])
        effect.blendMode = .add
        effect.alpha = intensity
        effect.zPosition = -1

        let copy = SKLabelNode()
        copy.numberOfLines = label.numberOfLines
        copy.lineBreakMode = label.lineBreakMode
        copy.preferredMaxLayoutWidth = label.preferredMaxLayoutWidth
        copy.horizontalAlignmentMode = label.horizontalAlignmentMode
        copy.verticalAlignmentMode = label.verticalAlignmentMode
        copy.attributedText = glow
        effect.addChild(copy)
        label.addChild(effect)
    }

    /// Four corner brackets around a point — a lock-on.
    func bracket(around center: CGPoint, halfWidth: CGFloat, halfHeight: CGFloat, arm: CGFloat,
                 color: UIColor, alpha: Float, width: CGFloat = 1.3) {
        for (sx, sy) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] as [(CGFloat, CGFloat)] {
            let corner = CGPoint(x: center.x + halfWidth * sx, y: center.y + halfHeight * sy)
            canvas.line2D(corner, CGPoint(x: corner.x - arm * sx, y: corner.y), color: color, alpha: alpha, width: width)
            canvas.line2D(corner, CGPoint(x: corner.x, y: corner.y - arm * sy), color: color, alpha: alpha, width: width)
        }
    }
}
