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

        if let view = self.view as! SKView? {
            // Create menu scene (intro screen)
            let scene = MenuScene(size: view.bounds.size)
            scene.scaleMode = .resizeFill

            // Present scene
            view.presentScene(scene)

            view.ignoresSiblingOrder = true
            // view.showsFPS = true
            // view.showsNodeCount = true
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        // Game is designed for portrait mode
        return .portrait
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
