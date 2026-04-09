//
//  SceneDelegate.swift
//  StashNativeSample
//

import UIKit

/// Navigation controller that forwards supportedInterfaceOrientations to its top view controller.
/// This mirrors how Unity's UnityAppController and Unreal's IOSAppDelegate work — the root VC
/// controls the allowed orientations, letting ViewController simulate a landscape-locked game.
final class ForwardingNavigationController: UINavigationController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        topViewController?.supportedInterfaceOrientations ?? .all
    }
    override var shouldAutorotate: Bool {
        topViewController?.shouldAutorotate ?? true
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        let nav = ForwardingNavigationController(rootViewController: ViewController())
        nav.navigationBar.prefersLargeTitles = true
        window.rootViewController = nav
        self.window = window
        window.makeKeyAndVisible()

        if let url = connectionOptions.urlContexts.first?.url {
            _ = StashSampleDeepLink.handle(url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        _ = StashSampleDeepLink.handle(url)
    }
}
