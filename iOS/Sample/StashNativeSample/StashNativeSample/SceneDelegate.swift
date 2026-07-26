//
//  SceneDelegate.swift
//  StashNativeSample
//

import UIKit
import StashNative

/// Orientation comes from the root VC so the "Lock app to landscape" switch also
/// covers pushed screens. UINavigationController does not consult its children.
final class ForwardingNavigationController: UINavigationController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        viewControllers.first?.supportedInterfaceOrientations ?? .all
    }
    override var shouldAutorotate: Bool {
        viewControllers.first?.shouldAutorotate ?? true
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

        // Sample/QA build: allow Safari Web Inspector and Appium to inspect checkout webviews.
        StashNativeCard.setInspectableWebViewsEnabled(true)

        let window = UIWindow(windowScene: windowScene)
        let nav = ForwardingNavigationController(rootViewController: ViewController())
        nav.navigationBar.prefersLargeTitles = false
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
