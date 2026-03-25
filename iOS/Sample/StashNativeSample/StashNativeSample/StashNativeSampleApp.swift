//
//  StashNativeSampleApp.swift
//  StashNativeSample
//
//  Created by Ondřej Řeháček on 09.02.2026.
//

import UIKit
import StashNative

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        true
    }

    // Explicitly wire up SceneDelegate so iOS doesn't rely on plist class-name resolution.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        StashSampleDeepLink.handle(url)
    }
}

enum StashSampleDeepLink {
    static func handle(_ url: URL) -> Bool {
        let urlString = url.absoluteString

        if urlString.contains("stash/purchaseSuccess") {
            StashNativeCard.sharedInstance().dismissSafariViewController(withResult: true)
            return true
        }
        if urlString.contains("stash/purchaseFailure") {
            StashNativeCard.sharedInstance().dismissSafariViewController(withResult: false)
            return true
        }

        return false
    }
}
