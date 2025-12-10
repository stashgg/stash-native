//
//  AppDelegate.swift
//  StashPaySample
//
//  Sample iOS app demonstrating StashPayCard SDK integration.
//

import UIKit
// StashPay is imported via bridging header

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ViewController()
        window?.makeKeyAndVisible()
        
        return true
    }
    
    // Handle deep links for payment callbacks
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        let urlString = url.absoluteString
        
        if urlString.contains("stash/purchaseSuccess") {
            StashPayCard.sharedInstance().dismissSafariViewController(withResult: true)
            return true
        } else if urlString.contains("stash/purchaseFailure") {
            StashPayCard.sharedInstance().dismissSafariViewController(withResult: false)
            return true
        }
        
        return false
    }
}
