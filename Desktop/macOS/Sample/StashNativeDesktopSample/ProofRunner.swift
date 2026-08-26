//
//  ProofRunner.swift
//  StashNativeDesktopSample
//
//  -stash-auto <local|remote|secure>: hands-free proof runs for CI and humans. Prints
//  "STASH-PROOF <mode>: RESULT: PASS|FAIL" and exits with 0 / 1.
//
//    local   offline test page over the sample window, expects the full bridge round trip
//    remote  -stash-url <https://...>: the page must load (navigation, pageLoaded)
//    secure  file:// without allowFileUrls and http:// are both refused with the checkout closed
//

import AppKit
import StashNativeDesktop

final class ProofRunner {
    private let mode: String
    private let remoteUrl: String?
    private let timeout: TimeInterval = 25
    private var phase = 0

    init(mode: String, remoteUrl: String?) {
        self.mode = mode
        self.remoteUrl = remoteUrl
    }

    static func testPageUrl(_ name: String) -> String {
        // The shared pages live in the source tree next to this sample.
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let page = sourceDir.appendingPathComponent("../../../shared/test-pages/\(name)").standardized
        return page.absoluteString
    }

    private func log(_ line: String) {
        print("STASH-PROOF \(mode): \(line)")
        fflush(stdout)
    }

    private func finish(_ pass: Bool, _ detail: String) {
        log("RESULT: \(pass ? "PASS" : "FAIL") (\(detail))")
        log("events: \(EventLog.shared.types.joined(separator: " -> "))")
        StashNativeDesktop_Shutdown()
        exit(pass ? 0 : 1)
    }

    func start() {
        EventLog.shared.onEvent = { [weak self] entry in
            self?.log("event \(entry.type) \(entry.payload)")
            self?.evaluate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(false, "timeout after \(Int(self?.timeout ?? 0))s")
        }
        switch mode {
        case "local":
            let url = ProofRunner.testPageUrl("stash_test_checkout.html") + "?auto=1"
            log("opening \(url)")
            StashNativeCard.sharedInstance().openCard(withURL: url, configJSON: "{\"allowFileUrls\":true}")
        case "remote":
            guard let url = remoteUrl, !url.isEmpty else {
                finish(false, "pass -stash-url <https://checkout url>")
                return
            }
            log("opening \(url)")
            StashNativeCard.sharedInstance().openCard(withURL: url, config: nil)
        case "secure":
            phase = 1
            let url = ProofRunner.testPageUrl("stash_test_checkout.html")
            log("opening \(url) without allowFileUrls")
            StashNativeCard.sharedInstance().openCard(withURL: url, config: nil)
        default:
            finish(false, "unknown mode, use local | remote | secure")
        }
    }

    private func evaluate() {
        let types = EventLog.shared.types
        let presented = StashNativeCard.sharedInstance().isCurrentlyPresented
        switch mode {
        case "local":
            let expected = ["navigation", "pageLoaded", "purchaseProcessing", "paymentSuccess"]
            if types.count >= expected.count {
                let passed = Array(types.prefix(expected.count)) == expected && !presented
                finish(passed, passed ? "bridge round trip completed, checkout closed" : "unexpected sequence")
            } else if types.contains("networkError") {
                finish(false, "network error")
            }
        case "remote":
            if types.contains("pageLoaded") {
                StashNativeCard.sharedInstance().dismiss()
                finish(types.first == "navigation" && presented, "checkout loaded")
            } else if types.contains("networkError") {
                finish(false, "network error")
            }
        case "secure":
            evaluateSecure(types: types, presented: presented)
        default:
            break
        }
    }

    private func evaluateSecure(types: [String], presented: Bool) {
        // Each phase ends with navigationBlocked followed by networkError and no presentation.
        let phaseEvents = Array(types.suffix(from: min(types.count, (phase - 1) * 2)))
        guard phaseEvents.count >= 2 else { return }
        let passed = phaseEvents[0] == "navigationBlocked" && phaseEvents[1] == "networkError" && !presented
        if !passed {
            finish(false, "phase \(phase) expected navigationBlocked -> networkError")
            return
        }
        if phase == 1 {
            phase = 2
            log("phase 1 ok: file:// refused; opening http://example.com")
            StashNativeCard.sharedInstance().openCard(withURL: "http://example.com/", config: nil)
        } else {
            finish(true, "file:// and http:// refused, checkout never presented")
        }
    }
}
