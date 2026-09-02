//
//  main.swift
//  StashNativeDesktopSample
//
//  AppKit sample for the macOS desktop host. Run with `swift run StashNativeDesktopSample`
//  from Desktop/, or `-stash-auto <local|remote|secure> [-stash-url <url>]` for a proof run.
//

import AppKit
import StashNativeDesktop

func argumentValue(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: SampleWindow?
    private var proof: ProofRunner?

    func applicationDidFinishLaunching(_ notification: Notification) {
        EventLog.shared.install()
        let mainWindow = SampleWindow()
        window = mainWindow
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        StashNativeCard.sharedInstance().hostWindow = mainWindow
        StashNativeCard.sharedInstance().prewarm()

        if let mode = argumentValue("-stash-auto") {
            let runner = ProofRunner(mode: mode, remoteUrl: argumentValue("-stash-url"))
            proof = runner
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { runner.start() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        StashNativeCard.sharedInstance().shutdown()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
