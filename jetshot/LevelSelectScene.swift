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
    private var isInitialized = false

    // Swipe gesture tracking
    private var touchStartLocation: CGPoint?
    private var touchStartTime: TimeInterval = 0
    private var hasMoved = false

    override func didMove(to view: SKView) {
        backgroundColor = UITheme.Colors.sceneBackground

        // Get safe area insets
        if let windowScene = view.window?.windowScene {
            safeAreaTop = windowScene.windows.first?.safeAreaInsets.top ?? 0
            safeAreaBottom = windowScene.windows.first?.safeAreaInsets.bottom ?? 0
        }

        addChild(StarfieldHelper.createStarfield(for: self))
        addChild(StarfieldHelper.createShootingStars(for: self))
        addChild(StarfieldHelper.createMeteors(for: self))
        setupTitle(view: view)
        setupPageContainer()
        setupNavigationArrows()
        setupPageIndicator(view: view)
        setupBackButton(view: view)
        loadPage(currentPage)
        isInitialized = true

        // Start background music
        SoundManager.shared.startBackgroundMusic()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard isInitialized, let view = view else { return }

        // Update safe area insets
        if let windowScene = view.window?.windowScene {
            safeAreaTop = windowScene.windows.first?.safeAreaInsets.top ?? 0
            safeAreaBottom = windowScene.windows.first?.safeAreaInsets.bottom ?? 0
        }

        // Remove and recreate all elements
        removeAllChildren()

        addChild(StarfieldHelper.createStarfield(for: self))
        addChild(StarfieldHelper.createShootingStars(for: self))
        addChild(StarfieldHelper.createMeteors(for: self))
        setupTitle(view: view)
        setupPageContainer()
        setupNavigationArrows()
        setupPageIndicator(view: view)
        setupBackButton(view: view)
        loadPage(currentPage)
    }

    private func setupTitle(view: SKView) {
        let title = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        title.text = "SELECT LEVEL"
        title.fontSize = UITheme.Typography.sizeLarge
        title.fontColor = UITheme.Colors.primaryGold

        // Position below safe area with minimum margin for all devices
        let topMargin = max(safeAreaTop + 60, 70)
        title.position = CGPoint(x: size.width / 2, y: size.height - topMargin)
        addChild(title)

        // Pulsing glow effect
        title.run(UITheme.createGlowPulseAnimation())
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
        arrow.strokeColor = UITheme.Colors.textPrimary
        arrow.lineWidth = UITheme.Dimensions.lineWidthExtraThick
        arrow.lineCap = .round
        arrow.lineJoin = .round

        return arrow
    }

    private func setupPageIndicator(view: SKView) {
        pageIndicator = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
        pageIndicator.fontSize = UITheme.Typography.sizeTiny
        pageIndicator.fontColor = UITheme.Colors.textPrimary

        // Position above safe area (home indicator) with minimum margin for all devices
        let bottomMargin = max(safeAreaBottom + 110, 120)
        pageIndicator.position = CGPoint(x: size.width / 2, y: bottomMargin)
        addChild(pageIndicator)
        updatePageIndicator()
    }

    private func updateArrowsVisibility() {
        let totalPages = (levelManager.totalLevels + levelsPerPage - 1) / levelsPerPage
        leftArrow?.alpha = currentPage > 0 ? UITheme.Animations.alphaFull : UITheme.Animations.alphaInactive
        rightArrow?.alpha = currentPage < totalPages - 1 ? UITheme.Animations.alphaFull : UITheme.Animations.alphaInactive
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

        let buttonSize = UITheme.Dimensions.levelButtonSize
        let spacing = UITheme.Dimensions.levelButtonSpacing
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
            button.setScale(UITheme.Animations.scaleSmall)
            pageContainer.addChild(button)
            levelButtons.append(button)

            // Staggered entrance animation
            let delay = Double(index) * 0.05
            button.run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.group([
                    SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal),
                    SKAction.scale(to: UITheme.Animations.scaleNormal, duration: UITheme.Animations.durationNormal)
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

        // Enhanced button with hexagonal shape
        let button = createHexagonButton(size: size)

        if !isUnlocked {
            button.fillColor = UITheme.Colors.levelLocked
            button.strokeColor = UITheme.Colors.levelLockedBorder
        } else if isCompleted {
            button.fillColor = UITheme.Colors.levelCompleted
            button.strokeColor = UITheme.Colors.levelCompletedBorder

            // Add glow for completed levels
            GlowHelper.addEnhancedGlow(to: button, color: UITheme.Colors.levelCompletedBorder, intensity: 0.4)
        } else {
            button.fillColor = UITheme.Colors.levelUnlocked
            button.strokeColor = UITheme.Colors.levelUnlockedBorder

            // Add glow for available levels
            GlowHelper.addEnhancedGlow(to: button, color: UITheme.Colors.levelUnlockedBorder, intensity: 0.3)
        }
        button.lineWidth = UITheme.Dimensions.lineWidthThick
        container.addChild(button)

        // Add inner hexagon decoration
        let innerHex = createHexagonButton(size: size * 0.85)
        innerHex.fillColor = .clear
        innerHex.strokeColor = isUnlocked ? UITheme.Colors.highlightWhiteStrong : UIColor.gray.withAlphaComponent(0.1)
        innerHex.lineWidth = UITheme.Dimensions.lineWidthThin
        container.addChild(innerHex)

        // Level number with better styling
        let levelLabel = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        levelLabel.text = "\(level)"
        levelLabel.fontSize = UITheme.Typography.sizeMedium
        levelLabel.fontColor = isUnlocked ? UITheme.Colors.textLabel : UITheme.Colors.textLabelInactive
        levelLabel.horizontalAlignmentMode = .center
        levelLabel.verticalAlignmentMode = .center
        levelLabel.position = CGPoint(x: 0, y: 0)
        container.addChild(levelLabel)

        // Stars for completed levels
        if isCompleted {
            let starsEarned = levelManager.getLevelStars(level: level)

            for i in 0..<3 {
                let star = createEnhancedStar(radius: UITheme.Dimensions.starSmallRadius)
                star.position = CGPoint(
                    x: CGFloat(i - 1) * 14,
                    y: size / 2 + 16
                )

                // Fill based on stars earned
                if i < starsEarned {
                    star.fillColor = UITheme.Colors.primaryGold
                    star.strokeColor = UIColor(red: 1.0, green: 0.95, blue: 0.5, alpha: 1.0)

                    // Star animation only for earned stars
                    let rotate = SKAction.rotate(byAngle: .pi * 2, duration: 3.0)
                    star.run(SKAction.repeatForever(rotate))
                } else {
                    // Empty gray star for not earned
                    star.fillColor = UIColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 0.5)
                    star.strokeColor = UIColor(red: 0.4, green: 0.4, blue: 0.45, alpha: 0.8)
                }

                star.lineWidth = UITheme.Dimensions.lineWidthThin
                container.addChild(star)
            }
        }

        return container
    }

    private func createHexagonButton(size: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        let radius = size / 2
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3
            let x = radius * cos(angle)
            let y = radius * sin(angle)
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return SKShapeNode(path: path)
    }

    private func createEnhancedStar(radius: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        let points = 5
        let innerRadius = radius * 0.4

        for i in 0..<points * 2 {
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let currentRadius = i % 2 == 0 ? radius : innerRadius
            let x = currentRadius * cos(angle)
            let y = currentRadius * sin(angle)

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()

        return SKShapeNode(path: path)
    }

    private func createSmallStar() -> SKShapeNode {
        return createEnhancedStar(radius: 5)
    }

    private func setupBackButton(view: SKView) {
        let buttonWidth: CGFloat = 140
        let buttonSpacing: CGFloat = 10

        // Position above safe area (home indicator) with minimum margin for all devices
        let bottomMargin = max(safeAreaBottom + 60, 70)

        // Back button
        let backButton = UITheme.createButton(
            text: "BACK",
            color: UIColor(red: 0.5, green: 0.5, blue: 0.6, alpha: 1.0),
            width: buttonWidth,
            name: "backButton"
        )
        backButton.position = CGPoint(
            x: size.width / 2 - buttonWidth / 2 - buttonSpacing / 2,
            y: bottomMargin
        )
        backButton.alpha = 0
        addChild(backButton)

        // Reset button
        let resetButton = UITheme.createButton(
            text: "RESET",
            color: UIColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 0.5),
            width: buttonWidth,
            name: "resetButton"
        )
        resetButton.position = CGPoint(
            x: size.width / 2 + buttonWidth / 2 + buttonSpacing / 2,
            y: bottomMargin
        )
        resetButton.alpha = 0
        addChild(resetButton)

        // Fade in both buttons
        backButton.run(SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal))
        resetButton.run(SKAction.fadeIn(withDuration: UITheme.Animations.durationNormal))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Store touch start for swipe detection
        touchStartLocation = location
        touchStartTime = touch.timestamp
        hasMoved = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              let startLocation = touchStartLocation else { return }

        let currentLocation = touch.location(in: self)
        let deltaX = currentLocation.x - startLocation.x
        let deltaY = currentLocation.y - startLocation.y

        // Check if movement is significant (more than 10 points)
        if abs(deltaX) > 10 || abs(deltaY) > 10 {
            hasMoved = true
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              let startLocation = touchStartLocation else { return }

        let endLocation = touch.location(in: self)
        let deltaX = endLocation.x - startLocation.x
        let deltaY = endLocation.y - startLocation.y
        let duration = touch.timestamp - touchStartTime

        // Swipe detection parameters
        let minSwipeDistance: CGFloat = 50
        let maxSwipeDuration: TimeInterval = 0.5
        let maxVerticalDeviation: CGFloat = 100

        // Check if this is a horizontal swipe
        if abs(deltaX) > minSwipeDistance &&
           abs(deltaY) < maxVerticalDeviation &&
           duration < maxSwipeDuration {

            let totalPages = (levelManager.totalLevels + levelsPerPage - 1) / levelsPerPage

            // Swipe left (move to next page)
            if deltaX < 0 && currentPage < totalPages - 1 {
                HapticManager.shared.selection()
                SoundManager.shared.playMenuSelectSound(on: self)
                changePage(currentPage + 1)
                return
            }

            // Swipe right (move to previous page)
            if deltaX > 0 && currentPage > 0 {
                HapticManager.shared.selection()
                SoundManager.shared.playMenuSelectSound(on: self)
                changePage(currentPage - 1)
                return
            }
        }

        // If no swipe detected and no significant movement, treat as tap
        if !hasMoved {
            handleTap(at: endLocation)
        }

        // Reset tracking
        touchStartLocation = nil
        hasMoved = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Reset tracking
        touchStartLocation = nil
        hasMoved = false
    }

    private func handleTap(at location: CGPoint) {
        let touchedNode = atPoint(location)

        if let nodeName = touchedNode.name {
            // Back button (check both button and label)
            if nodeName == "backButton" || nodeName == "backButtonLabel" {
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                handleBackButton()
                return
            }

            // Reset button (check both button and label)
            if nodeName == "resetButton" || nodeName == "resetButtonLabel" {
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                handleResetButton()
                return
            }

            // Navigation arrows
            if nodeName == "leftArrow" && currentPage > 0 {
                HapticManager.shared.selection()
                SoundManager.shared.playMenuSelectSound(on: self)
                changePage(currentPage - 1)
                return
            }

            if nodeName == "rightArrow" {
                let totalPages = (levelManager.totalLevels + levelsPerPage - 1) / levelsPerPage
                if currentPage < totalPages - 1 {
                    HapticManager.shared.selection()
                    SoundManager.shared.playMenuSelectSound(on: self)
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

            // Confirmation dialog buttons
            if nodeName == "confirmYes" {
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                confirmReset()
                return
            }

            if nodeName == "confirmNo" {
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                dismissConfirmationDialog()
                return
            }
        }

        // Check if touched on a parent button
        if let parent = touchedNode.parent,
           let parentName = parent.name {
            // Check parent for back button
            if parentName == "backButton" {
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                handleBackButton()
                return
            }

            // Check parent for reset button
            if parentName == "resetButton" {
                HapticManager.shared.lightTap()
                SoundManager.shared.playButtonClickSound(on: self)
                handleResetButton()
                return
            }

            // Check parent for level button
            if parentName.hasPrefix("levelButton_") {
                if let levelString = parentName.split(separator: "_").last,
                   let level = Int(levelString) {
                    handleLevelTap(level: level)
                }
            }

            // Check parent for confirmation dialog buttons
            if parentName == "confirmYes" {
                HapticManager.shared.lightTap()
                confirmReset()
                return
            }

            if parentName == "confirmNo" {
                HapticManager.shared.lightTap()
                dismissConfirmationDialog()
                return
            }
        }
    }

    private func changePage(_ newPage: Int) {
        guard newPage != currentPage else { return }

        let isMovingForward = newPage > currentPage

        // Slide out current page
        let slideOut = isMovingForward ?
            SKAction.moveBy(x: -size.width, y: 0, duration: 0.3) :
            SKAction.moveBy(x: size.width, y: 0, duration: 0.3)
        let fadeOut = SKAction.fadeOut(withDuration: 0.3)

        pageContainer.run(SKAction.group([slideOut, fadeOut])) { [weak self] in
            guard let self = self else { return }
            self.currentPage = newPage
            self.pageContainer.position = CGPoint(
                x: self.size.width / 2 + (isMovingForward ? self.size.width : -self.size.width),
                y: self.size.height / 2 + 20
            )
            self.loadPage(newPage)
            self.updateArrowsVisibility()
            self.updatePageIndicator()

            // Slide in new page with fade in
            let slideIn = SKAction.moveTo(x: self.size.width / 2, duration: 0.3)
            let fadeIn = SKAction.fadeIn(withDuration: 0.3)
            self.pageContainer.run(SKAction.group([slideIn, fadeIn]))
        }
    }

    private func handleLevelTap(level: Int) {
        if levelManager.isLevelUnlocked(level) {
            HapticManager.shared.lightTap()
            SoundManager.shared.playButtonClickSound(on: self)

            // Button press animation
            if let button = levelButtons.first(where: { $0.name == "levelButton_\(level)" }) {
                let scaleDown = SKAction.scale(to: 0.9, duration: 0.1)
                let scaleUp = SKAction.scale(to: 1.0, duration: 0.1)
                button.run(SKAction.sequence([scaleDown, scaleUp])) { [weak self] in
                    self?.startLevel(level)
                }
            }
        } else {
            HapticManager.shared.warning()
            SoundManager.shared.playHitSound(on: self)
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
        // Button press animation
        if let backButton = childNode(withName: "backButton") {
            backButton.run(UITheme.createButtonPressAnimation { [weak self] in
                self?.goToMenu()
            })
        }
    }

    private func handleResetButton() {
        // Button press animation
        if let resetButton = childNode(withName: "resetButton") {
            resetButton.run(UITheme.createButtonPressAnimation { [weak self] in
                self?.showConfirmationDialog()
            })
        }
    }

    private func showConfirmationDialog() {
        // Create overlay
        let overlay = SKShapeNode(rectOf: CGSize(width: size.width, height: size.height))
        overlay.fillColor = UIColor.black.withAlphaComponent(0.7)
        overlay.strokeColor = .clear
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.zPosition = 100
        overlay.name = "confirmationOverlay"
        overlay.alpha = 0
        addChild(overlay)

        // Create dialog box
        let dialogWidth: CGFloat = 320
        let dialogHeight: CGFloat = 205
        let topBottomMargin: CGFloat = 20  // Same margin for top and bottom
        let dialog = SKShapeNode(
            rectOf: CGSize(width: dialogWidth, height: dialogHeight),
            cornerRadius: UITheme.Dimensions.cornerRadiusLarge
        )
        dialog.fillColor = UIColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1.0)
        dialog.strokeColor = UITheme.Colors.primaryCyan
        dialog.lineWidth = UITheme.Dimensions.lineWidthThick
        dialog.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dialog.zPosition = 101
        dialog.name = "confirmationDialog"
        dialog.setScale(0.8)
        dialog.alpha = 0
        addChild(dialog)

        // Add glow to dialog
        GlowHelper.addEnhancedGlow(to: dialog, color: UITheme.Colors.primaryCyan, intensity: 0.5)

        // Title
        let title = SKLabelNode(fontNamed: UITheme.Typography.fontBold)
        title.text = "RESET PROGRESS?"
        title.fontSize = UITheme.Typography.sizeMedium
        title.fontColor = UITheme.Colors.dangerRed
        title.position = CGPoint(x: 0, y: dialogHeight / 2 - topBottomMargin - 14)
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        dialog.addChild(title)

        // Message
        let message = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
        message.text = "All level progress will be lost."
        message.fontSize = UITheme.Typography.sizeSmall
        message.fontColor = UITheme.Colors.textPrimary
        message.position = CGPoint(x: 0, y: 25)
        message.horizontalAlignmentMode = .center
        message.verticalAlignmentMode = .center
        dialog.addChild(message)

        let message2 = SKLabelNode(fontNamed: UITheme.Typography.fontRegular)
        message2.text = "This action cannot be undone!"
        message2.fontSize = UITheme.Typography.sizeSmall
        message2.fontColor = UITheme.Colors.textSecondary
        message2.position = CGPoint(x: 0, y: 1)
        message2.horizontalAlignmentMode = .center
        message2.verticalAlignmentMode = .center
        dialog.addChild(message2)

        // No button (left side)
        let buttonWidth: CGFloat = 120
        let buttonHeight: CGFloat = 40 // Shorter buttons for dialog
        let buttonYPosition = -dialogHeight / 2 + topBottomMargin + buttonHeight / 2 + 10
        let noButton = UITheme.createButton(
            text: "NO",
            color: UIColor(red: 0.4, green: 0.8, blue: 0.4, alpha: 1.0),
            width: buttonWidth,
            name: "confirmNo",
            height: buttonHeight
        )
        noButton.position = CGPoint(x: -buttonWidth / 2 - 10, y: buttonYPosition)
        dialog.addChild(noButton)

        // Yes button (right side)
        let yesButton = UITheme.createButton(
            text: "YES",
            color: UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1.0),
            width: buttonWidth,
            name: "confirmYes",
            height: buttonHeight
        )
        yesButton.position = CGPoint(x: buttonWidth / 2 + 10, y: buttonYPosition)
        dialog.addChild(yesButton)

        // Animate in
        overlay.run(SKAction.fadeIn(withDuration: 0.2))
        dialog.run(SKAction.group([
            SKAction.fadeIn(withDuration: 0.2),
            SKAction.scale(to: 1.0, duration: 0.2)
        ]))
    }

    private func dismissConfirmationDialog() {
        if let overlay = childNode(withName: "confirmationOverlay"),
           let dialog = childNode(withName: "confirmationDialog") {
            overlay.run(SKAction.fadeOut(withDuration: 0.2)) {
                overlay.removeFromParent()
            }
            dialog.run(SKAction.group([
                SKAction.fadeOut(withDuration: 0.2),
                SKAction.scale(to: 0.8, duration: 0.2)
            ])) {
                dialog.removeFromParent()
            }
        }
    }

    private func confirmReset() {
        HapticManager.shared.warning()

        // Reset progress
        levelManager.resetProgress()

        // Dismiss dialog
        if let overlay = childNode(withName: "confirmationOverlay"),
           let dialog = childNode(withName: "confirmationDialog") {
            overlay.run(SKAction.fadeOut(withDuration: 0.2)) {
                overlay.removeFromParent()
            }
            dialog.run(SKAction.group([
                SKAction.fadeOut(withDuration: 0.2),
                SKAction.scale(to: 0.8, duration: 0.2)
            ])) {
                dialog.removeFromParent()
            }
        }

        // Reload current page to reflect changes
        let delay = SKAction.wait(forDuration: 0.3)
        run(delay) { [weak self] in
            guard let self = self else { return }
            self.loadPage(self.currentPage)
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
