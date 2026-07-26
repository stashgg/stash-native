//
//  ViewController+StashNativeDelegate.swift
//  StashNativeSample
//
//  StashNativeCardDelegate implementation for ViewController.
//

import UIKit
import StashNative

// MARK: - StashNativeCardDelegate

extension ViewController: StashNativeCardDelegate {

    func stashNativeCardDidCompletePayment(withOrder order: String?) {
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

    func stashNativeCardDidFailPayment() {
        DispatchQueue.main.async {
            self.addCallbackChip("Payment Failure")
        }
    }

    func stashNativeCardDidDismiss() {
        DispatchQueue.main.async {
            self.addCallbackChip("Dialog Dismissed")
            self.flushPendingAlertsIfPossible()
        }
    }

    func stashNativeCardDidReceiveOpt(in optinType: String) {
        DispatchQueue.main.async {
            self.addCallbackChip("Opt-In: \(optinType)")
        }
    }

    func stashNativeCardDidLoadPage(_ loadTimeMs: Double) {
        DispatchQueue.main.async {
            self.addCallbackChip("Page Loaded · \(Int(loadTimeMs)) ms")
        }
    }

    func stashNativeCardDidEncounterNetworkError() {
        DispatchQueue.main.async {
            self.addCallbackChip("Network Error")
        }
    }

    func stashNativeCardDidRequestExternalPayment(with url: String) {
        DispatchQueue.main.async {
            self.addCallbackChip("External Payment")
        }
    }

    func stashNativeCardDidCloseBrowser() {
        DispatchQueue.main.async {
            self.addCallbackChip("Browser Closed")
        }
    }
}
