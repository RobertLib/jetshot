//
//  GameViewController.swift
//  jetshot
//
//  Created by Robert Libšanský on 16.10.2025.
//

import UIKit
import SpriteKit
import GameplayKit

class GameViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let view = self.view as? SKView else {
            assertionFailure("View is not SKView")
            return
        }

        // Create menu scene (intro screen).
        //
        // `DebugLaunch` returns something else only when the App Store media pipeline
        // has passed it a launch argument; it is `#if DEBUG` and returns nil for every
        // ordinary launch, so the menu stays the one and only entry point in Release.
        var scene: SKScene = MenuScene(size: view.bounds.size)
        #if DEBUG
        scene = DebugLaunch.makeInitialScene(size: view.bounds.size) ?? scene
        #endif
        scene.scaleMode = .resizeFill

        // Present scene
        view.presentScene(scene)

        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = true
        view.preferredFramesPerSecond = 60
        // view.showsFPS = true
        // view.showsNodeCount = true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        // Game is designed for portrait mode
        return .portrait
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
