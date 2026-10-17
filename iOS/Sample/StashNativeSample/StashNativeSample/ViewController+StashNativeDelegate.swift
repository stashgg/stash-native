//
//  ViewController+StashNativeDelegate.swift
//  StashNativeSample
//
//  StashNativeDelegate implementation for ViewController.
//

import UIKit
import StashNative

// MARK: - StashNativeDelegate

extension ViewController: StashNativeDelegate {

    func stashNativeDidScanQRCode(_ content: String) {
        addCallbackChip("CodeLink · \(content)")
        flushPendingAlertsIfPossible()
    }

    func stashNativeCodeLinkDidEncounterError(_ error: Error) {
        addCallbackChip("CodeLink · \(error.localizedDescription)")
    }

    func stashNativeDidCompletePayment(withOrder order: String?) {
        let label: String
        if let order, !order.isEmpty {
            label = "Payment Success · \(order)"
        } else {
            label = "Payment Success"
        }
        DispatchQueue.main.async {
            self.addCallbackChip(label)
        }
    }

    func stashNativeDidFailPayment() {
        DispatchQueue.main.async {
            self.addCallbackChip("Payment Failure")
        }
    }

    func stashNativeDidDismissCard() {
        recordDismissal("Card Dismissed")
    }

    func stashNativeDidDismissScan() {
        recordDismissal("Scan Dismissed")
    }

    private func recordDismissal(_ label: String) {
        DispatchQueue.main.async {
            self.addCallbackChip(label)
            self.flushPendingAlertsIfPossible()
        }
    }

    func stashNativeDidLoadPage(_ loadTimeMs: Double) {
        DispatchQueue.main.async {
            self.addCallbackChip("Page Loaded · \(Int(loadTimeMs)) ms")
        }
    }

    func stashNativeDidEncounterNetworkError() {
        DispatchQueue.main.async {
            self.addCallbackChip("Network Error")
        }
    }

    func stashNativeDidRequestExternalPayment(with url: String) {
        DispatchQueue.main.async {
            self.addCallbackChip("External Payment")
        }
    }

    func stashNativeDidDismissBrowser() {
        recordDismissal("Browser Dismissed")
    }

}
