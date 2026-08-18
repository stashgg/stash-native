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
        StashNativeCard.sharedInstance().openCard(withURL: url, config: config)
    }

    @objc func openDeeplinkTestTapped() {
        let config = buildCardConfig()
        StashNativeCard.sharedInstance().openCard(withURL: DeeplinkTestHarness.dataURL(), config: config)
    }

    @objc func openBrowserTapped() {
        let url = (browserUrlTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            showAlert(title: "Error", message: "Please enter a browser URL")
            return
        }
        StashNativeCard.sharedInstance().openBrowser(withURL: url)
    }

    func buildCardConfig() -> StashNativeCardConfig {
        let config = StashNativeCardConfig()
        config.forcePortrait = forcePortraitOnCheckoutSwitch.isOn
        config.cardHeightRatioPortrait = CGFloat(phoneCardHeightSlider.value) / 100.0
        config.cardWidthRatioLandscape = CGFloat(checkoutPhoneLandscapeWidthSlider.value) / 100.0
        config.cardHeightRatioLandscape = CGFloat(checkoutPhoneLandscapeHeightSlider.value) / 100.0
        config.tabletWidthRatioPortrait = CGFloat(checkoutTabletPortraitWidthSlider.value) / 100.0
        config.tabletHeightRatioPortrait = CGFloat(checkoutTabletPortraitHeightSlider.value) / 100.0
        config.tabletWidthRatioLandscape = CGFloat(checkoutTabletLandscapeWidthSlider.value) / 100.0
        config.tabletHeightRatioLandscape = CGFloat(checkoutTabletLandscapeHeightSlider.value) / 100.0
        config.autoClose = cardAutoCloseSwitch.isOn
        if let hex = trimmedHex(cardBackgroundColorTextField) {
            config.backgroundColor = hex
        }
        return config
    }

    @objc func openModalTapped() {
        let url = (modalUrlTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            showAlert(title: "Error", message: "Please enter a modal URL")
            return
        }
        let config = buildModalConfig()
        StashNativeCard.sharedInstance().openModal(withURL: url, config: config)
    }

    func buildModalConfig() -> StashNativeModalConfig {
        let config = StashNativeModalConfig()
        config.allowDismiss = modalAllowDismissSwitch.isOn
        config.phoneWidthRatioPortrait = CGFloat(modalPhonePortraitWidthSlider.value) / 100.0
        config.phoneHeightRatioPortrait = CGFloat(modalPhonePortraitHeightSlider.value) / 100.0
        config.phoneWidthRatioLandscape = CGFloat(modalPhoneLandscapeWidthSlider.value) / 100.0
        config.phoneHeightRatioLandscape = CGFloat(modalPhoneLandscapeHeightSlider.value) / 100.0
        config.tabletWidthRatioPortrait = CGFloat(modalTabletPortraitWidthSlider.value) / 100.0
        config.tabletHeightRatioPortrait = CGFloat(modalTabletPortraitHeightSlider.value) / 100.0
        config.tabletWidthRatioLandscape = CGFloat(modalTabletLandscapeWidthSlider.value) / 100.0
        config.tabletHeightRatioLandscape = CGFloat(modalTabletLandscapeHeightSlider.value) / 100.0
        config.autoClose = modalAutoCloseSwitch.isOn
        if let hex = trimmedHex(modalBackgroundColorTextField) {
            config.backgroundColor = hex
        }
        return config
    }

    @objc func openCardOptionsTapped() {
        navigationController?.pushViewController(
            OptionsListViewController(mode: .card, host: self), animated: true)
    }

    @objc func openModalOptionsTapped() {
        navigationController?.pushViewController(
            OptionsListViewController(mode: .modal, host: self), animated: true)
    }

    @objc func sliderValueChanged(_ sender: UISlider) {
        sliderLabels[sender]?.text = "\(Int(sender.value))%"
    }

    @objc func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc func generateCheckoutTapped() {
        performGenerateUrl(.checkout) { [weak self] checkoutUrl in
            guard let self = self else { return }
            let config = self.buildCardConfig()
            StashNativeCard.sharedInstance().openCard(withURL: checkoutUrl, config: config)
        }
    }

    @objc func generateCheckoutForBrowserTapped() {
        performGenerateUrl(.checkout) { checkoutUrl in
            StashNativeCard.sharedInstance().openBrowser(withURL: checkoutUrl)
        }
    }

    @objc func openWebshopTapped() {
        performGenerateUrl(.webshop) { [weak self] webshopUrl in
            guard let self = self else { return }
            let config = self.buildCardConfig()
            StashNativeCard.sharedInstance().openCard(withURL: webshopUrl, config: config)
        }
    }

    @objc func openWebshopForBrowserTapped() {
        performGenerateUrl(.webshop) { webshopUrl in
            StashNativeCard.sharedInstance().openBrowser(withURL: webshopUrl)
        }
    }

    /// Trimmed hex from a color field, or nil when the field is blank.
    private func trimmedHex(_ field: UITextField) -> String? {
        let hex = field.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return hex.isEmpty ? nil : hex
    }

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
