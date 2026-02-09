//
//  StashNativeSampleApp.swift
//  StashNativeSample
//
//  Created by Ondřej Řeháček on 09.02.2026.
//

import UIKit
import StashNative
// StashNative is imported via bridging header

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        window = UIWindow(frame: UIScreen.main.bounds)
        let nav = UINavigationController(rootViewController: ViewController())
        nav.navigationBar.prefersLargeTitles = true
        window?.rootViewController = nav
        window?.makeKeyAndVisible()

        return true
    }

    // Handle deep links for payment callbacks
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        let urlString = url.absoluteString

        if urlString.contains("stash/purchaseSuccess") {
            StashNativeCard.sharedInstance().dismissSafariViewController(withResult: true)
            return true
        } else if urlString.contains("stash/purchaseFailure") {
            StashNativeCard.sharedInstance().dismissSafariViewController(withResult: false)
            return true
        }

        return false
    }
}
