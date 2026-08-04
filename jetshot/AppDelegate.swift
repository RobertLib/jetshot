//
//  AppDelegate.swift
//  jetshot
//
//  Created by Robert Libšanský on 16.10.2025.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // No `window` property here. Under the UIScene life cycle the window belongs to
    // the scene, not the application — see `SceneDelegate.window`. The one that used
    // to sit here was never assigned by anything anyway.

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.

        // Initialize iCloud storage (this will start synchronization)
        _ = CloudStorageManager.shared

        // Optional: Print iCloud status for debugging
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            CloudStorageManager.shared.printCloudStatus()
        }
        #endif

        return true
    }

    // No app-lifecycle hooks here on purpose. Pausing and resuming gameplay is driven
    // by GameScene, which observes UIApplication.willResignActive / didBecomeActive
    // directly — see GameScene.appWillResignActive(). The empty Xcode template stubs
    // that used to sit here just invited someone to add a second, competing pause path.
    //
    // Those two notifications are still posted in a scene-based app; it is the
    // *delegate* callbacks (applicationDidBecomeActive(_:) and friends) that stop
    // being called once the scene manifest is present, which is why there was nothing
    // to migrate.

    // MARK: - UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Called when a new scene session is being created. The single configuration
        // this returns is the one declared in Info.plist, which names SceneDelegate.
        return UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }
}
