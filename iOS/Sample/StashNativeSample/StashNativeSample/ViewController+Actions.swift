//
//  ViewController+Actions.swift
//  StashNativeSample
//
//  Action methods for ViewController.
//

import UIKit
import StashNative

// MARK: - Actions

extension ViewController {

    @objc func lockLandscapeToggled(_ sender: UISwitch) {
        lockLandscape = sender.isOn
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            navigationController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    @objc func openCardTapped() {
        let url = (checkoutUrlTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            showAlert(title: "Error", message: "Please enter a card URL")
            return
        }
        let config = buildCardConfig()
        StashNativeCard.sharedInstance().openCard(withURL: url, from: self, config: config)
    }

    @objc func openBrowserTapped() {
        let url = (browserUrlTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            showAlert(title: "Error", message: "Please enter a browser URL")
            return
        }
        StashNativeCard.sharedInstance().openBrowser(withURL: url, from: self)
    }

    func buildCardConfig() -> StashNativeCardConfig {
        let config = StashNativeCardConfig()
        config.orientationPreference = cardPreferPortraitSwitch.isOn ? .portrait : .followHost
        config.preferredContentWidth = CGFloat(cardPreferredWidthSlider.value)
        config.preferredContentHeight = CGFloat(cardPreferredHeightSlider.value)
        config.maximumContentHeight = CGFloat(cardMaximumHeightSlider.value)
        config.edgeMargin = CGFloat(cardEdgeMarginSlider.value)
        config.allowDismiss = cardAllowDismissSwitch.isOn
        config.autoClose = cardAutoCloseSwitch.isOn
        return config
    }

    @objc func openCardOptionsTapped() {
        navigationController?.pushViewController(
            OptionsListViewController(host: self), animated: true)
    }

    @objc func sliderValueChanged(_ sender: UISlider) {
        sender.value = sender.value.rounded()
        let isMaximum = sender === cardMaximumHeightSlider
        let value = isMaximum && sender.value == 0 ? "Available" : "\(Int(sender.value)) pt"
        sliderLabels[sender]?.text = value
        sender.accessibilityValue = value
    }

    @objc func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc func generateCheckoutTapped() {
        performGenerateUrl(.checkout) { [weak self] checkoutUrl in
            guard let self = self else { return }
            let config = self.buildCardConfig()
            StashNativeCard.sharedInstance().openCard(withURL: checkoutUrl, from: self, config: config)
        }
    }

    @objc func generateCheckoutForBrowserTapped() {
        performGenerateUrl(.checkout) { [weak self] checkoutUrl in
            guard let self = self else { return }
            StashNativeCard.sharedInstance().openBrowser(withURL: checkoutUrl, from: self)
        }
    }

    @objc func openWebshopTapped() {
        performGenerateUrl(.webshop) { [weak self] webshopUrl in
            guard let self = self else { return }
            let config = self.buildCardConfig()
            StashNativeCard.sharedInstance().openCard(withURL: webshopUrl, from: self, config: config)
        }
    }

    @objc func openWebshopForBrowserTapped() {
        performGenerateUrl(.webshop) { [weak self] webshopUrl in
            guard let self = self else { return }
            StashNativeCard.sharedInstance().openBrowser(withURL: webshopUrl, from: self)
        }
    }

    #if DEBUG
    func openLaunchPresentationIfNeeded() {
        guard !handledLaunchPresentation, presentedViewController == nil else { return }
        handledLaunchPresentation = true
        let arguments = ProcessInfo.processInfo.arguments
        guard let urlIndex = arguments.firstIndex(of: "-stash-url"),
              arguments.indices.contains(urlIndex + 1),
              let url = URL(string: arguments[urlIndex + 1]),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        let modeIndex = arguments.firstIndex(of: "-stash-mode")
        let mode = modeIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "card"
        if mode == "browser" {
            browserUrlTextField.text = url.absoluteString
            openBrowserTapped()
        } else if mode == "card" {
            checkoutUrlTextField.text = url.absoluteString
            openCardTapped()
        }
    }
    #endif

    /// Calls the Stash server endpoint for `kind` and returns the generated URL.
    private func performGenerateUrl(_ kind: ViewController.PayloadKind,
                                    onSuccess: @escaping (String) -> Void) {
        let path = kind == .checkout
            ? "/sdk/server/checkout_links/generate_quick_pay_url"
            : "/sdk/server/generate_url"
        let failureMessage = kind == .checkout
            ? "Failed to generate checkout URL"
            : "Failed to generate webshop URL"
        let baseUrl = isActiveKeyProduction() ? "https://api.stash.gg" : "https://test-api.stash.gg"
        guard let url = URL(string: baseUrl + path) else {
            showAlert(title: "Error", message: failureMessage)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Body is the active instance's saved payload for this endpoint, sent verbatim.
        // Sign the exact bytes that go on the wire, then send them unchanged.
        let bodyData = Data(activePayload(kind).utf8)
        guard let signature = StashHmac.signature(
                appId: activeAppId(), ingressSecretB64: activeApiKey(), body: bodyData) else {
            showAlert(title: "Error", message: failureMessage)
            return
        }
        request.setValue(signature, forHTTPHeaderField: "x-stash-hmac-signature")
        request.httpBody = bodyData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self else { return }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let isSuccessResponse = statusCode >= 200 && statusCode < 300
            guard isSuccessResponse, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let generatedUrl = json["url"] as? String, !generatedUrl.isEmpty else {
                DispatchQueue.main.async {
                    self.showAlert(title: "Error", message: failureMessage)
                }
                return
            }
            DispatchQueue.main.async {
                onSuccess(generatedUrl)
            }
        }.resume()
    }
}
