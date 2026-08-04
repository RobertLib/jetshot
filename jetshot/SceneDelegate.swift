//
//  SceneDelegate.swift
//  jetshot
//

import UIKit

/// Window-scene owner for the app.
///
/// Exists so the app runs on the UIScene life cycle rather than the legacy
/// UIApplication one. On iOS 26 the legacy path logs a runtime fault at launch
/// ("`UIScene` lifecycle will soon be required..."), and Apple has said apps that
/// have not adopted it will eventually fail to launch. See `Info.plist` for the
/// manifest that names this class.
///
/// Deliberately thin. Pausing and resuming gameplay is *not* wired up here: it is
/// driven by `GameScene`, which observes the app's active/inactive notifications
/// itself (see `GameScene.appWillResignActive()`). Adding a second pause path here
/// would fight the first — `togglePause()` toggles rather than sets, so two callers
/// per transition would cancel each other out and leave the game running behind the
/// pause menu.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    /// Populated by UIKit from `UISceneStoryboardFile` before `scene(_:willConnectTo:)`
    /// runs. Storyboard-driven apps do not build this themselves.
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // Main.storyboard has already been loaded and attached to `window` by this
        // point, so there is nothing to construct — only the scene type to confirm.
        guard scene is UIWindowScene else { return }
    }
}
