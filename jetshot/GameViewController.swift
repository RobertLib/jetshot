//
//  GameViewController.swift
//  jetshot
//
//  Created by Robert Libšanský on 16.10.2025.
//

import UIKit
import SpriteKit

class GameViewController: UIViewController {

    /// Set once the first scene is up. See `viewDidLayoutSubviews()`.
    private var hasPresentedInitialScene = false

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let view = self.view as? SKView else {
            assertionFailure("View is not SKView")
            return
        }

        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = true
        view.preferredFramesPerSecond = 60
        // view.showsFPS = true
        // view.showsNodeCount = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-stats") {
            view.showsFPS = true
            view.showsNodeCount = true
            view.showsDrawCount = true
        }
        #endif
    }

    /// Presents the first scene, on the first layout pass that has the real screen.
    ///
    /// Not from `viewDidLoad()`, which is where it used to be. At that point the view is
    /// still the storyboard's 375×667 and in no window, so its safe-area insets read 0,
    /// and every scene measures its layout once, as it arrives. The menu rebuilt itself
    /// on the resize that followed, but with the insets it had cached at 0, so the
    /// credits and the timecode sat a little off; the DEBUG `-results` and `-story`
    /// routes, which do not rebuild on that resize at all, came up framed for a 667pt
    /// screen. By the first layout the view is in its window and sized to it.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !hasPresentedInitialScene,
              let view = self.view as? SKView,
              view.window != nil,
              view.bounds.width > 0, view.bounds.height > 0 else { return }
        hasPresentedInitialScene = true

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

        view.presentScene(scene)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        // Game is designed for portrait mode
        return .portrait
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    /// The ship flies its lowest row a thumb's width above the bottom edge, so a drag
    /// down there is part of play, not a request to leave. Deferred, the first swipe up
    /// from the edge only brings the home indicator back and it takes a second to go
    /// home; without it a steering drag that strayed onto the edge ended the session
    /// mid-run.
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        return .bottom
    }

    /// Kept out of the picture, as the status bar is. It reappears on a touch near the
    /// edge, and the deferral above relies on that: it is the first swipe's feedback.
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
}
