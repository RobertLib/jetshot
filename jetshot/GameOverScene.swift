//
//  GameOverScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.10.2025.
//

import SpriteKit

/// The run is over, told in the boss warning's language: the world on red alert, a
/// flatline where the ship's signal was, and the title glitching in over it.
class GameOverScene: SKScene {

    /// Shared vertical rhythm for the results screens. See `UITheme.PanelRhythm`.
    private typealias Rhythm = UITheme.PanelRhythm

    private let finalScore: Int
    private let currentLevel: Int
    private let isEndless: Bool
    private let endlessRound: Int
    /// Whether this run beat the stored endless best. Decided by `GameScene.gameOver()`,
    /// which records the run — by the time this scene exists the store already holds the
    /// new figure, so comparing here would compare the run against itself.
    private let isEndlessRecord: Bool
    private var isInitialized = false
    /// Every button here leaves the screen, once. See `FilmUI.Exit`.
    private let exit = FilmUI.Exit()

    private static let red = StoryPalette.red

    init(
        size: CGSize,
        score: Int,
        level: Int = 1,
        isEndless: Bool = false,
        endlessRound: Int = 0,
        isEndlessRecord: Bool = false
    ) {
        self.finalScore = score
        self.currentLevel = level
        self.isEndless = isEndless
        self.endlessRound = endlessRound
        self.isEndlessRecord = isEndlessRecord
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = UITheme.Colors.sceneBackground
        buildScene()
        isInitialized = true

        // Continue background music
        SoundManager.shared.resumeMusic()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        // Not while leaving — see `LevelCompleteScene.didChangeSize(_:)`.
        guard isInitialized, !exit.isTaken else { return }
        removeAllChildren()
        buildScene()
    }

    override func willMove(from view: SKView) {
        removeAllActions()
        removeAllChildren()
    }

    private func buildScene() {
        GameBackdrop.attachAmbient(to: self, look: isEndless ? .forEndlessRound(1) : .forLevel(currentLevel)).setAlert(true)
        NeonFX.attachGrade(to: self, zPosition: -5)
        addAlertGrade()
        setupUI()
    }

    /// The edges of the picture burn red and breathe, as they do under the boss warning.
    private func addAlertGrade() {
        let grade = NeonFX.gradeOverlay(size: size)
        grade.name = "alertGrade"
        grade.color = Self.red
        grade.colorBlendFactor = 1
        grade.blendMode = .add
        grade.alpha = 0
        grade.zPosition = -4
        addChild(grade)

        let breathe = SKAction.sequence([
            .fadeAlpha(to: 0.42, duration: 1.4),
            .fadeAlpha(to: 0.2, duration: 1.4)
        ])
        grade.run(.sequence([.fadeAlpha(to: 0.6, duration: 0.25), .fadeAlpha(to: 0.3, duration: 0.6),
                             .repeatForever(breathe)]))
    }

    private func setupUI() {
        let card = ResultsCard(sceneWidth: size.width)
        let red = Self.red
        let tint = StoryPalette.mix(red, .white, 0.3)

        let sector = (currentLevel - 1) / 5 + 1
        let tag = card.tag(
            isEndless
                ? "\(L10n.HUD.endless)  ·  \(L10n.HUD.round(max(1, endlessRound)))"
                : "\(L10n.HUD.level(currentLevel))  ·  \(L10n.Sector.name(sector))",
            color: tint, delay: 0.25
        )
        card.add(tag, gapAbove: Rhythm.edge, height: 14, reveal: false)

        let flatline = createFlatline(width: min(card.width, 220))
        card.add(flatline, gapAbove: 18, height: 40, reveal: false)

        let title = FilmUI.title(L10n.GameOver.title, size: 34, color: StoryPalette.mix(red, .white, 0.2),
                                 glow: red, tracking: 6, maxWidth: card.width)
        title.alpha = 0
        card.add(title, gapAbove: 16, height: title.frame.height, reveal: false)

        let rule = FilmUI.drawnRule(width: min(card.width, 220), color: red, alpha: 0.6, delay: 0.75)
        card.add(rule, gapAbove: 14, height: 1, reveal: false)

        let figures = createScoreDisplay(card: card)
        card.add(figures.node, gapAbove: Rhythm.aroundFigures, height: figures.height)

        let retryButton = UITheme.createButton(text: L10n.Common.retry, color: red,
                                               width: card.primaryButtonWidth, name: "retryButton", primary: true)
        let levelsButton = UITheme.createButton(text: L10n.Common.levels, color: FilmUI.neutral,
                                                width: card.pairButtonWidth, name: "levelsButton")
        let menuButton = UITheme.createButton(text: L10n.Common.menu, color: FilmUI.neutral,
                                              width: card.pairButtonWidth, name: "menuButton")
        card.addButtons(primary: retryButton, pair: (levelsButton, menuButton), gapAbove: Rhythm.aroundFigures)

        card.install(in: self, accent: red,
                     safeTop: GameConfiguration.safeAreaTop(in: view),
                     safeBottom: GameConfiguration.safeAreaBottom(in: view),
                     revealFrom: 0.9)

        // The title lands hard, jittering, as the boss warning's does.
        title.run(FilmUI.glitchIn(title, delay: 0.6))
    }

    /// The figures under the title, spaced by `UITheme.PanelRhythm` and centred on the
    /// returned node's origin, with the height the outer stack needs.
    private func createScoreDisplay(card: ResultsCard) -> (node: SKNode, height: CGFloat) {
        let container = SKNode()

        let caption = card.caption(L10n.Common.score)
        let value = card.figure(finalScore, color: .white)

        // The caption rides tight against the number it labels; anything further down
        // is a separate figure and gets the wider gap.
        var rows: [(label: SKLabelNode, gapAbove: CGFloat)] = [
            (caption, 0),
            (value, Rhythm.captionToValue)
        ]

        // Endless has no completion screen, so the run's result is reported here or
        // nowhere: how deep it got, and whether it beat the standing record.
        if isEndless {
            rows.append((card.line(L10n.GameOver.reachedRound(endlessRound), color: UITheme.Colors.primaryCyanLight),
                         Rhythm.figureLine))

            if isEndlessRecord {
                let record = card.line(L10n.GameOver.newRecord, color: UITheme.Colors.improvement)
                record.run(.sequence([
                    .wait(forDuration: 2.0),
                    .repeatForever(.sequence([.fadeAlpha(to: 0.45, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)]))
                ]))
                rows.append((record, Rhythm.figureLine))
            } else {
                let records = LevelManager.shared.getEndlessRecords()
                rows.append((card.line(L10n.Common.endlessRecord(score: records.bestScore, round: records.bestRound),
                                       color: UITheme.Colors.textSecondary),
                             Rhythm.figureLine))
            }
        }

        // Named so `ResultsPanelCentringTests` can find the block it is asserting on;
        // nothing looks it up at runtime.
        container.name = "figureBlock"

        let height = UITheme.stackLabels(rows, in: container)
        FilmUI.countUp(value, to: finalScore, delay: 1.0, duration: 0.7, glow: StoryPalette.ice)
        return (container, height)
    }

    /// The ship's signal: a heartbeat traced in red light that spikes once and then
    /// runs flat.
    private func createFlatline(width: CGFloat) -> SKNode {
        let node = SKNode()
        let half = width / 2
        let points: [CGPoint] = [
            CGPoint(x: -half, y: 0), CGPoint(x: -half * 0.34, y: 0), CGPoint(x: -half * 0.24, y: 6),
            CGPoint(x: -half * 0.16, y: -4), CGPoint(x: -half * 0.08, y: 18), CGPoint(x: 0, y: -16),
            CGPoint(x: half * 0.08, y: 4), CGPoint(x: half * 0.14, y: 0), CGPoint(x: half, y: 0)
        ]
        // Traced left to right, a segment at a time, so the beat happens and then stops.
        var delay: TimeInterval = 0.3
        for (a, b) in zip(points, points.dropFirst()) {
            let segment = FilmUI.tube(a, b, width: 1.6, color: Self.red)
            segment.alpha = 0
            let length = hypot(b.x - a.x, b.y - a.y)
            segment.run(.sequence([.wait(forDuration: delay), .fadeIn(withDuration: 0.05)]))
            node.addChild(segment)
            delay += TimeInterval(length / width) * 0.5
        }

        // The point of the trace, running ahead of it and dying out at the end.
        let head = LightSprite.star(size: 22, color: StoryPalette.mix(Self.red, .white, 0.5))
        head.position = points[0]
        head.alpha = 0
        var path: [SKAction] = [.wait(forDuration: 0.3), .fadeIn(withDuration: 0.05)]
        for (a, b) in zip(points, points.dropFirst()) {
            path.append(.move(to: b, duration: TimeInterval(hypot(b.x - a.x, b.y - a.y) / width) * 0.5))
        }
        path.append(.fadeOut(withDuration: 0.4))
        head.run(.sequence(path))
        node.addChild(head)

        // And once it has run flat, the whole trace slowly dims and returns, like a
        // monitor still listening.
        node.run(.sequence([
            .wait(forDuration: delay + 0.6),
            .repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 1.2), .fadeAlpha(to: 0.85, duration: 1.2)]))
        ]))
        return node
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !exit.isTaken, let touch = touches.first else { return }
        let location = touch.location(in: self)

        guard let button = FilmUI.button(at: location, under: self,
                                         names: ["retryButton", "levelsButton", "menuButton"]),
              exit.take() else { return }
        HapticManager.shared.lightTap()
        SoundManager.shared.playButtonClickSound(on: self)

        let action: () -> Void
        switch button.name {
        case "retryButton": action = { [weak self] in self?.restartGame() }
        case "levelsButton": action = { [weak self] in self?.goToLevelSelect() }
        default: action = { [weak self] in self?.goToMenu() }
        }
        button.run(UITheme.createButtonPressAnimation(completion: action))
    }

    private func restartGame() {
        exit.present(from: self) { size in
            let gameScene = GameScene(size: size)
            gameScene.currentLevel = currentLevel // Restart the same level
            // RETRY on an endless run starts another endless run, not the campaign.
            gameScene.isEndless = isEndless

            // Load weapon arsenal from previous level when restarting. Endless always
            // starts from the default loadout — carrying an arsenal into an unbounded
            // score chase would make the record depend on campaign progress rather than
            // on the run.
            if !isEndless, currentLevel > 1 {
                let weapons = LevelManager.shared.getLevelWeapons(level: currentLevel - 1)
                gameScene.startingBulletCount = weapons.bulletCount
                gameScene.startingSideMissileCount = weapons.sideMissileCount
            }
            return gameScene
        }
    }

    private func goToLevelSelect() {
        exit.present(from: self) { LevelSelectScene(size: $0, startLevel: currentLevel) }
    }

    private func goToMenu() {
        exit.present(from: self) { MenuScene(size: $0) }
    }
}
