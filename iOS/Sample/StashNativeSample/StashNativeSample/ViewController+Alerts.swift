//
//  ViewController+Alerts.swift
//  StashNativeSample
//
//  Alerts are queued: the SDK can report an outcome while another alert is still up.
//

import UIKit

extension ViewController {

    func showAlert(title: String, message: String) {
        print("[StashSample] alert queued: \(title) -- \(message)")
        pendingAlerts.append((title, message))
        flushPendingAlertsIfPossible()
    }

    func flushPendingAlertsIfPossible() {
        // present() sets presentedViewController synchronously, so this alone guards re-entry.
        guard presentedViewController == nil, !pendingAlerts.isEmpty else { return }
        let (title, message) = pendingAlerts.removeFirst()
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.flushPendingAlertsIfPossible()
            }
        })
        present(alert, animated: true)
    }
}
