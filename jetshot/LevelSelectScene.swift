//
//  LevelSelectScene.swift
//  jetshot
//
//  Created by Robert Libšanský on 18.10.2025.
//

import SpriteKit

class LevelSelectScene: SKScene {

    private let levelManager = LevelManager.shared
    private var levelButtons: [SKNode] = []
    private var currentPage = 0
    private let levelsPerPage = 12 // 3 columns x 4 rows

    private var pageContainer: SKNode!
    private var leftArrow: SKShapeNode?
    private var rightArrow: SKShapeNode?
    private var pageIndicator: SKLabelNode!

    private var safeAreaTop: CGFloat = 0
    private var safeAreaBottom: CGFloat = 0

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)

        // Get safe area insets
        if let windowScene = view.window?.windowScene {
            safeAreaTop = windowScene.windows.first?.safeAreaInsets.top ?? 0
            safeAreaBottom = windowScene.windows.first?.safeAreaInsets.bottom ?? 0
        }

        addChild(StarfieldHelper.createStarfield(for: self))
        setupTitle(view: view)
        setupPageContainer()
        setupNavigationArrows()
        setupPageIndicator(view: view)
        setupBackButton(view: view)
        loadPage(currentPage)
    }

    private func setupTitle(view: SKView) {
        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text = "SELECT LEVEL"
        title.fontSize = 32
        title.fontColor = UIColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)

        // Position below safe area with minimum margin for all devices
        let topMargin = max(safeAreaTop + 60, 70)
        title.position = CGPoint(x: size.width / 2, y: size.height - topMargin)
        addChild(title)

        // Pulsing glow effect
        let fadeOut = SKAction.fadeAlpha(to: 0.7, duration: 1.0)
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 1.0)
        let pulse = SKAction.sequence([fadeOut, fadeIn])
        title.run(SKAction.repeatForever(pulse))
    }

    private func setupPageContainer() {
        pageContainer = SKNode()
        pageContainer.position = CGPoint(x: size.width / 2, y: size.height / 2 + 20)
        addChild(pageContainer)
    }

    private func setupNavigationArrows() {
        let arrowMargin: CGFloat = 30

        // Left arrow - tip is at x: 0
        leftArrow = createArrow(pointingLeft: true)
        leftArrow!.position = CGPoint(x: arrowMargin, y: size.height / 2 + 20)
        leftArrow!.name = "leftArrow"
        addChild(leftArrow!)

        // Right arrow - tip is at x: 0
        rightArrow = createArrow(pointingLeft: false)
        rightArrow!.position = CGPoint(x: size.width - arrowMargin, y: size.height / 2 + 20)
        rightArrow!.name = "rightArrow"
        addChild(rightArrow!)

        updateArrowsVisibility()
    }

    private func createArrow(pointingLeft: Bool) -> SKShapeNode {
        let path = CGMutablePath()
        let size: CGFloat = 15

        if pointingLeft {
            // Tip pointing left, tail pointing right
            path.move(to: CGPoint(x: size, y: size))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: size, y: -size))
        } else {
            // Tip pointing right, tail pointing left
            path.move(to: CGPoint(x: -size, y: size))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: -size, y: -size))
        }

        let arrow = SKShapeNode(path: path)
        arrow.strokeColor = .white
        arrow.lineWidth = 4
        arrow.lineCap = .round
        arrow.lineJoin = .round

        return arrow
    }

    private func setupPageIndicator(view: SKView) {
        pageIndicator = SKLabelNode(fontNamed: "Arial")
        pageIndicator.fontSize = 16
        pageIndicator.fontColor = .white

        // Position above safe area (home indicator) with minimum margin for all devices
        let bottomMargin = max(safeAreaBottom + 110, 120)
        pageIndicator.position = CGPoint(x: size.width / 2, y: bottomMargin)
        addChild(pageIndicator)
        updatePageIndicator()
    }

    private func updateArrowsVisibility() {
        let totalPages = (levelManager.totalLevels + levelsPerPage - 1) / levelsPerPage
        leftArrow?.alpha = currentPage > 0 ? 1.0 : 0.3
        rightArrow?.alpha = currentPage < totalPages - 1 ? 1.0 : 0.3
    }

    private func updatePageIndicator() {
        let totalPages = (levelManager.totalLevels + levelsPerPage - 1) / levelsPerPage
        pageIndicator.text = "Page \(currentPage + 1) / \(totalPages)"
    }

    private func loadPage(_ page: Int) {
        // Clear existing buttons
        pageContainer.removeAllChildren()
        levelButtons.removeAll()

        let startLevel = page * levelsPerPage + 1
        let endLevel = min(startLevel + levelsPerPage - 1, levelManager.totalLevels)

        let buttonSize: CGFloat = 70
        let spacing: CGFloat = 20
        let columns = 3
        let rows = 4

        // Calculate grid offset to center it
        let gridWidth = CGFloat(columns) * buttonSize + CGFloat(columns - 1) * spacing
        let gridHeight = CGFloat(rows) * buttonSize + CGFloat(rows - 1) * spacing
        let startX = -gridWidth / 2 + buttonSize / 2
        let startY = gridHeight / 2 - buttonSize / 2

        var index = 0
        for level in startLevel...endLevel {
            let row = index / columns
            let col = index % columns

            let x = startX + CGFloat(col) * (buttonSize + spacing)
            let y = startY - CGFloat(row) * (buttonSize + spacing)

            let button = createLevelButton(level: level, size: buttonSize)
            button.position = CGPoint(x: x, y: y)
            button.alpha = 0
            button.setScale(0.5)
            pageContainer.addChild(button)
            levelButtons.append(button)

            // Staggered entrance animation
            let delay = Double(index) * 0.05
            button.run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.group([
                    SKAction.fadeIn(withDuration: 0.3),
                    SKAction.scale(to: 1.0, duration: 0.3)
                ])
            ]))

            index += 1
        }
    }

    private func createLevelButton(level: Int, size: CGFloat) -> SKNode {
        let container = SKNode()
        container.name = "levelButton_\(level)"

        let isUnlocked = levelManager.isLevelUnlocked(level)
        let isCompleted = levelManager.isLevelCompleted(level)

        // Button circle
        let button = SKShapeNode(circleOfRadius: size / 2)

        if !isUnlocked {
            button.fillColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
            button.strokeColor = UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
        } else if isCompleted {
            button.fillColor = UIColor(red: 0.2, green: 0.6, blue: 0.2, alpha: 1.0)
            button.strokeColor = UIColor(red: 0.3, green: 0.8, blue: 0.3, alpha: 1.0)
        } else {
            button.fillColor = UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
            button.strokeColor = UIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)
        }
        button.lineWidth = 3
        container.addChild(button)

        // Level number
        let levelLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        levelLabel.text = "\(level)"
        levelLabel.fontSize = 24
        levelLabel.fontColor = isUnlocked ? .white : UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        levelLabel.horizontalAlignmentMode = .center
        levelLabel.verticalAlignmentMode = .center
        levelLabel.position = .zero
        container.addChild(levelLabel)

        // Stars for completed levels
        if isCompleted {
            for i in 0..<3 {
                let star = createSmallStar()
                star.position = CGPoint(
                    x: CGFloat(i - 1) * 12,
                    y: size / 2 + 10
                )
                star.fillColor = UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
                star.strokeColor = .clear
                container.addChild(star)
            }
        }

        // Lock icon for locked levels
        if !isUnlocked {
            let lock = SKLabelNode(fontNamed: "Arial")
            lock.text = "🔒"
            lock.fontSize = 20
            lock.position = CGPoint(x: 0, y: -8)
            container.addChild(lock)
        }

        return container
    }

    private func createSmallStar() -> SKShapeNode {
        let path = CGMutablePath()
        let points = 5
        let outerRadius: CGFloat = 5
        let innerRadius: CGFloat = 2.5

        for i in 0..<points * 2 {
            let angle = CGFloat(i) * .pi / CGFloat(points)
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let x = radius * cos(angle - .pi / 2)
            let y = radius * sin(angle - .pi / 2)

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()

        return SKShapeNode(path: path)
    }

    private func setupBackButton(view: SKView) {
        let button = SKShapeNode(rectOf: CGSize(width: 140, height: 45), cornerRadius: 12)
        let fillColor = UIColor(red: 0.3, green: 0.3, blue: 0.4, alpha: 1.0)
        button.fillColor = fillColor
        button.strokeColor = UIColor(red: 0.5, green: 0.5, blue: 0.6, alpha: 1.0) // Lighter version of fill color
        button.lineWidth = 3

        // Position above safe area (home indicator) with minimum margin for all devices
        let bottomMargin = max(safeAreaBottom + 60, 70)
        button.position = CGPoint(x: size.width / 2, y: bottomMargin)
        button.name = "backButton"
        button.alpha = 0

        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.text = "◀ BACK"
        label.fontSize = 18
        label.fontColor = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.name = "backButtonLabel"
        button.addChild(label)

        addChild(button)

        // Fade in only, no pulse animation
        button.run(SKAction.fadeIn(withDuration: 0.3))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let touchedNode = atPoint(location)

        if let nodeName = touchedNode.name {
            // Back button (check both button and label)
            if nodeName == "backButton" || nodeName == "backButtonLabel" {
                handleBackButton()
                return
            }

            // Navigation arrows
            if nodeName == "leftArrow" && currentPage > 0 {
                changePage(currentPage - 1)
                return
            }

            if nodeName == "rightArrow" {
                let totalPages = (levelManager.totalLevels + levelsPerPage - 1) / levelsPerPage
                if currentPage < totalPages - 1 {
                    changePage(currentPage + 1)
                }
                return
            }

            // Level button tapped
            if nodeName.hasPrefix("levelButton_") {
                if let levelString = nodeName.split(separator: "_").last,
                   let level = Int(levelString) {
                    handleLevelTap(level: level)
                }
            }
        }

        // Check if touched on a parent button
        if let parent = touchedNode.parent,
           let parentName = parent.name {
            // Check parent for back button
            if parentName == "backButton" {
                handleBackButton()
                return
            }

            // Check parent for level button
            if parentName.hasPrefix("levelButton_") {
                if let levelString = parentName.split(separator: "_").last,
                   let level = Int(levelString) {
                    handleLevelTap(level: level)
                }
            }
        }
    }

    private func changePage(_ newPage: Int) {
        guard newPage != currentPage else { return }

        // Slide out current page
        let slideOut = newPage > currentPage ?
            SKAction.moveBy(x: -size.width, y: 0, duration: 0.3) :
            SKAction.moveBy(x: size.width, y: 0, duration: 0.3)
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)

        pageContainer.run(SKAction.group([slideOut, fadeOut])) { [weak self] in
            guard let self = self else { return }
            self.currentPage = newPage
            self.pageContainer.position = CGPoint(
                x: self.size.width / 2 + (newPage > self.currentPage ? self.size.width : -self.size.width),
                y: self.size.height / 2 + 20
            )
            self.loadPage(newPage)
            self.updateArrowsVisibility()
            self.updatePageIndicator()

            // Slide in new page
            let slideIn = SKAction.moveTo(x: self.size.width / 2, duration: 0.3)
            self.pageContainer.run(slideIn)
        }

        currentPage = newPage
        updateArrowsVisibility()
        updatePageIndicator()
    }

    private func handleLevelTap(level: Int) {
        if levelManager.isLevelUnlocked(level) {
            // Button press animation
            if let button = levelButtons.first(where: { $0.name == "levelButton_\(level)" }) {
                let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
                let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
                button.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                    self?.startLevel(level)
                }
            }
        } else {
            // Show locked feedback
            if let button = levelButtons.first(where: { $0.name == "levelButton_\(level)" }) {
                let shake = SKAction.sequence([
                    SKAction.rotate(byAngle: -0.1, duration: 0.05),
                    SKAction.rotate(byAngle: 0.2, duration: 0.1),
                    SKAction.rotate(byAngle: -0.2, duration: 0.1),
                    SKAction.rotate(byAngle: 0.1, duration: 0.05)
                ])
                button.run(shake)
            }
        }
    }

    private func handleBackButton() {
        // Play sound
        SoundManager.shared.playShoot()

        // Button press animation
        if let backButton = childNode(withName: "backButton") {
            let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
            let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
            backButton.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                self?.goToMenu()
            }
        }
    }

    private func startLevel(_ level: Int) {
        let gameScene = GameScene(size: size)
        gameScene.currentLevel = level
        gameScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view?.presentScene(gameScene, transition: transition)
    }

    private func goToMenu() {
        let menuScene = MenuScene(size: size)
        menuScene.scaleMode = scaleMode
        let transition = SKTransition.fade(withDuration: 0.5)
        view?.presentScene(menuScene, transition: transition)
    }
}
