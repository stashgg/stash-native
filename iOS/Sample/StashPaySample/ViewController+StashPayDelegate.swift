//
//  ViewController+StashPayDelegate.swift
//  StashPaySample
//
//  StashPayCardDelegate implementation for ViewController.
//

import UIKit

// MARK: - StashPayCardDelegate

extension ViewController: StashPayCardDelegate {

    func stashPayCardDidCompletePayment() {
        DispatchQueue.main.async {
            self.showAlert(title: "Success", message: "Purchase Successful")
        }
    }

    func stashPayCardDidFailPayment() {
        DispatchQueue.main.async {
            self.showAlert(title: "Payment Failed", message: "Purchase Failed")
        }
    }

    func stashPayCardDidDismiss() {}

    func stashPayCardDidReceiveOpt(in optinType: String) {
        DispatchQueue.main.async {
            self.showAlert(title: "Opt-in", message: "Opt-in Selected: \(optinType)")
        }
    }

    func stashPayCardDidLoadPage(_ loadTimeMs: Double) {}

    func stashPayCardDidEncounterNetworkError() {
        // No outcome row for network error per plan
    }
}
