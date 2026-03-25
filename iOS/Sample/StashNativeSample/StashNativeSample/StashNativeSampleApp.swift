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
