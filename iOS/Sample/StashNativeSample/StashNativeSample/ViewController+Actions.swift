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

    @objc func forcePortraitOnCheckoutToggled(_ sender: UISwitch) {
        // Config is built at open time; no-op here.
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

    @objc func phoneCardHeightChanged() {
        phoneCardHeightLabel.text = "\(Int(phoneCardHeightSlider.value))%"
    }
    @objc func checkoutTabletPortraitWidthChanged() {
        checkoutTabletPortraitWidthLabel.text = "\(Int(checkoutTabletPortraitWidthSlider.value))%"
    }
    @objc func checkoutTabletPortraitHeightChanged() {
        checkoutTabletPortraitHeightLabel.text = "\(Int(checkoutTabletPortraitHeightSlider.value))%"
    }
    @objc func checkoutTabletLandscapeWidthChanged() {
        checkoutTabletLandscapeWidthLabel.text = "\(Int(checkoutTabletLandscapeWidthSlider.value))%"
    }
    @objc func checkoutTabletLandscapeHeightChanged() {
        checkoutTabletLandscapeHeightLabel.text = "\(Int(checkoutTabletLandscapeHeightSlider.value))%"
    }
    @objc func checkoutPhoneLandscapeWidthChanged() {
        checkoutPhoneLandscapeWidthLabel.text = "\(Int(checkoutPhoneLandscapeWidthSlider.value))%"
    }
    @objc func checkoutPhoneLandscapeHeightChanged() {
        checkoutPhoneLandscapeHeightLabel.text = "\(Int(checkoutPhoneLandscapeHeightSlider.value))%"
    }
    @objc func modalPhonePortraitWidthChanged() {
        modalPhonePortraitWidthLabel.text = "\(Int(modalPhonePortraitWidthSlider.value))%"
    }
    @objc func modalPhonePortraitHeightChanged() {
        modalPhonePortraitHeightLabel.text = "\(Int(modalPhonePortraitHeightSlider.value))%"
    }
    @objc func modalPhoneLandscapeWidthChanged() {
        modalPhoneLandscapeWidthLabel.text = "\(Int(modalPhoneLandscapeWidthSlider.value))%"
    }
    @objc func modalPhoneLandscapeHeightChanged() {
        modalPhoneLandscapeHeightLabel.text = "\(Int(modalPhoneLandscapeHeightSlider.value))%"
    }
    @objc func modalTabletPortraitWidthChanged() {
        modalTabletPortraitWidthLabel.text = "\(Int(modalTabletPortraitWidthSlider.value))%"
    }
    @objc func modalTabletPortraitHeightChanged() {
        modalTabletPortraitHeightLabel.text = "\(Int(modalTabletPortraitHeightSlider.value))%"
    }
    @objc func modalTabletLandscapeWidthChanged() {
        modalTabletLandscapeWidthLabel.text = "\(Int(modalTabletLandscapeWidthSlider.value))%"
    }
    @objc func modalTabletLandscapeHeightChanged() {
        modalTabletLandscapeHeightLabel.text = "\(Int(modalTabletLandscapeHeightSlider.value))%"
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

    // swiftlint:disable:next function_body_length
    private func performGenerateQuickPayCheckout(onSuccess: @escaping (String) -> Void) {
        let baseUrl = useTestApiSwitch.isOn ? "https://test-api.stash.gg" : "https://api.stash.gg"
        let urlString = baseUrl + "/sdk/server/checkout_links/generate_quick_pay_url"
        guard let url = URL(string: urlString) else {
            showAlert(title: "Error", message: "Failed to generate checkout URL")
            return
        }
        let apiKey = apiKeyTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ViewController.defaultStashApiKey
        if !apiKey.isEmpty {
            UserDefaults.standard.set(apiKey, forKey: ViewController.userDefaultsApiKeyKey)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-stash-api-key")
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
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            showAlert(title: "Error", message: "Failed to generate checkout URL")
            return
        }
        request.httpBody = bodyData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self else { return }
            let isSuccessResponse = (response as? HTTPURLResponse)?.statusCode ?? 0 >= 200
                && (response as? HTTPURLResponse)?.statusCode ?? 0 < 300
            guard isSuccessResponse, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let checkoutUrl = json["url"] as? String, !checkoutUrl.isEmpty else {
                DispatchQueue.main.async {
                    self.showAlert(title: "Error", message: "Failed to generate checkout URL")
                }
                return
            }
            DispatchQueue.main.async {
                onSuccess(checkoutUrl)
            }
        }.resume()
    }

    private func performGenerateAuthenticatedWebshopUrl(onSuccess: @escaping (String) -> Void) {
        let baseUrl = useTestApiSwitch.isOn ? "https://test-api.stash.gg" : "https://api.stash.gg"
        let urlString = baseUrl + "/sdk/server/generate_url"
        guard let url = URL(string: urlString) else {
            showAlert(title: "Error", message: "Failed to generate webshop URL")
            return
        }
        let trimmedApiKey = apiKeyTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let apiKey = trimmedApiKey.isEmpty ? ViewController.defaultStashApiKey : trimmedApiKey
        if !apiKey.isEmpty {
            UserDefaults.standard.set(apiKey, forKey: ViewController.userDefaultsApiKeyKey)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-stash-api-key")
        let body: [String: Any] = [
            "user": [
                "id": "7849fbc5-87fd-446d-8d9c-de25298f1092",
                "validatedEmail": "test@stash.gg",
                "displayName": "Test User",
                "platform": "IOS"
            ],
            "target": "STORE"
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            showAlert(title: "Error", message: "Failed to generate webshop URL")
            return
        }
        request.httpBody = bodyData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self else { return }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let isSuccessResponse = statusCode >= 200 && statusCode < 300
            guard isSuccessResponse, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let webshopUrl = json["url"] as? String, !webshopUrl.isEmpty else {
                DispatchQueue.main.async {
                    self.showAlert(title: "Error", message: "Failed to generate webshop URL")
                }
                return
            }
            DispatchQueue.main.async {
                onSuccess(webshopUrl)
            }
        }.resume()
    }
}
