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

    @objc func simulateLandscapeToggled(_ sender: UISwitch) {
        simulateLandscapeGame = sender.isOn
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
            navigationController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    @objc func openCardTapped() {
        guard let url = checkoutUrlTextField.text, !url.isEmpty else {
            showAlert(title: "Error", message: "Please enter a URL")
            return
        }
        let config = buildCardConfig()
        StashNativeCard.sharedInstance().openCard(withURL: url, config: config)
    }

    @objc func openBrowserTapped() {
        guard let url = browserUrlTextField.text, !url.isEmpty else {
            showAlert(title: "Error", message: "Please enter a URL")
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
        let hex = cardBackgroundColorTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !hex.isEmpty {
            config.backgroundColor = hex
        }
        return config
    }

    @objc func openModalTapped() {
        guard let url = modalUrlTextField.text, !url.isEmpty else {
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
        let hex = modalBackgroundColorTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !hex.isEmpty {
            config.backgroundColor = hex
        }
        return config
    }

    @objc func checkoutOptionsToggleTapped() {
        isCheckoutAdvancedExpanded.toggle()
        tableView.reloadSections(IndexSet(integer: Section.presentationOptions.rawValue), with: .automatic)
    }

    @objc func modalOptionsToggleTapped() {
        isModalAdvancedExpanded.toggle()
        tableView.reloadSections(IndexSet(integer: Section.presentationOptions.rawValue), with: .automatic)
    }

    // Updates the slider's label in sliderLabels to the slider value as a percentage.
    @objc func sliderValueChanged(_ sender: UISlider) {
        sliderLabels[ObjectIdentifier(sender)]?.text = "\(Int(sender.value))%"
    }

    @objc func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc func generateCheckoutTapped() {
        performGenerateQuickPayCheckout { [weak self] checkoutUrl in
            guard let self = self else { return }
            let config = self.buildCardConfig()
            StashNativeCard.sharedInstance().openCard(withURL: checkoutUrl, config: config)
        }
    }

    @objc func generateCheckoutForBrowserTapped() {
        performGenerateQuickPayCheckout { checkoutUrl in
            StashNativeCard.sharedInstance().openBrowser(withURL: checkoutUrl)
        }
    }

    @objc func openWebshopTapped() {
        performGenerateAuthenticatedWebshopUrl { [weak self] webshopUrl in
            guard let self = self else { return }
            let config = self.buildCardConfig()
            StashNativeCard.sharedInstance().openCard(withURL: webshopUrl, config: config)
        }
    }

    private func performGenerateQuickPayCheckout(onSuccess: @escaping (String) -> Void) {
        // Test fixture user and product data.
        let body: [String: Any] = [
            "user": [
                "id": "7849fbc5-87fd-446d-8d9c-de25298f1092",
                "validatedEmail": "test@stash.gg",
                "displayName": "Test User",
                "profileImageUrl":
                    "https://storage.googleapis.com/stash-demo-f9550.firebasestorage.app/avatars/"
                    + "6564ced3-c163-4b0d-aa4e-c1a19e42aa65.png",
                "platform": "IOS"
            ],
            "item": [
                "id": "realMoneyProduct_gems_001",
                "name": "Handful of Blackstone",
                "pricePerItem": "1.99",
                "quantity": 1,
                "imageUrl": "https://static.stash.gg/stash_logo_128.png"
            ],
            "currency": "USD",
            "createPaymentIntent": true,
            "transactionId": "6ef37116-e16f-43c6-ac72-8741c0bbd2b5",
            "regionCode": "US",
            "bonusItems": [
                [
                    "id": "196492b7-78f1-4875-bfb5-ff612b46c1f9",
                    "name": "Bonus Item",
                    "imageUrl": "https://static.stash.gg/stash_logo_128.png",
                    "quantity": 1
                ]
            ]
        ]
        performStashPost(
            path: "/sdk/server/checkout_links/generate_quick_pay_url",
            body: body,
            errorMessage: "Failed to generate checkout URL",
            onSuccess: onSuccess
        )
    }

    private func performGenerateAuthenticatedWebshopUrl(onSuccess: @escaping (String) -> Void) {
        // Test fixture user data.
        let body: [String: Any] = [
            "user": [
                "id": "7849fbc5-87fd-446d-8d9c-de25298f1092",
                "validatedEmail": "test@stash.gg",
                "displayName": "Test User",
                "platform": "IOS"
            ],
            "target": "STORE"
        ]
        performStashPost(
            path: "/sdk/server/generate_url",
            body: body,
            errorMessage: "Failed to generate webshop URL",
            onSuccess: onSuccess
        )
    }

    /// POSTs JSON to the Stash API with the effective key and calls onSuccess with the returned `url`.
    private func performStashPost(
        path: String, body: [String: Any], errorMessage: String,
        onSuccess: @escaping (String) -> Void
    ) {
        let baseUrl = useTestApiSwitch.isOn ? "https://test-api.stash.gg" : "https://api.stash.gg"
        guard let url = URL(string: baseUrl + path),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            showAlert(title: "Error", message: errorMessage)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(effectiveApiKey, forHTTPHeaderField: "x-stash-api-key")
        request.httpBody = bodyData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self else { return }
            guard self.isSuccessStatus(response), let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let resultUrl = json["url"] as? String, !resultUrl.isEmpty else {
                DispatchQueue.main.async {
                    self.showAlert(title: "Error", message: errorMessage)
                }
                return
            }
            DispatchQueue.main.async {
                onSuccess(resultUrl)
            }
        }.resume()
    }

    /// True for a 2xx HTTP response.
    private func isSuccessStatus(_ response: URLResponse?) -> Bool {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return code >= 200 && code < 300
    }
}
