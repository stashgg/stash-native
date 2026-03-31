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
        let message: String
        if let order, !order.isEmpty {
            message = "Purchase Successful\n\nOrder:\n\(order)"
        } else {
            message = "Purchase Successful"
        }
        DispatchQueue.main.async {
            self.showAlert(title: "Success", message: message)
        }
    }

    func stashNativeCardDidFailPayment() {
        DispatchQueue.main.async {
            self.showAlert(title: "Payment Failed", message: "Purchase Failed")
        }
    }

    func stashNativeCardDidDismiss() {}

    func stashNativeCardDidReceiveOpt(in optinType: String) {
        DispatchQueue.main.async {
            self.showAlert(title: "Opt-in", message: "Opt-in Selected: \(optinType)")
        }
    }

    func stashNativeCardDidLoadPage(_ loadTimeMs: Double) {}

    func stashNativeCardDidEncounterNetworkError() {
        DispatchQueue.main.async {
            self.showAlert(
                title: "Network Error",
                message: "Failed to load checkout. Please check your connection and try again."
            )
        }
    }

    func stashNativeCardDidRequestExternalPayment(with url: String) {
        // window.stash_sdk.openExternalBrowser(url) — card already closed; Safari / Custom Tabs opened by SDK
        print("External payment URL: \(url)")
    }
}
