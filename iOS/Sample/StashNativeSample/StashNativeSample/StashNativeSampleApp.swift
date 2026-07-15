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
        guard url.scheme?.lowercased() == "stashdemo" else { return false }
        let urlString = url.absoluteString

        if urlString.contains("stash-pay/success") {
            StashNativeCard.sharedInstance().dismissSafariViewController(withResult: true)
            return true
        }
        if urlString.contains("stash-pay/failure") {
            StashNativeCard.sharedInstance().dismissSafariViewController(withResult: false)
            return true
        }
        if urlString.contains("stash-pay/cancel") {
            StashNativeCard.sharedInstance().closeBrowser()
            return true
        }

        // Pass-through deeplink: close the in-app browser and surface the URL
        // (parity with the Android sample's outcome dialog).
        StashNativeCard.sharedInstance().closeBrowser()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let alert = UIAlertController(title: "Deeplink", message: urlString, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            top?.present(alert, animated: true)
        }
        return true
    }
}
