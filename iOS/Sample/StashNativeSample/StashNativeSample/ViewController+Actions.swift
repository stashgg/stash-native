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
        config.showDragBar = modalShowDragBarSwitch.isOn
        config.allowDismiss = modalAllowDismissSwitch.isOn
        config.phoneWidthRatioPortrait = CGFloat(modalPhonePortraitWidthSlider.value) / 100.0
        config.phoneHeightRatioPortrait = CGFloat(modalPhonePortraitHeightSlider.value) / 100.0
        config.phoneWidthRatioLandscape = CGFloat(modalPhoneLandscapeWidthSlider.value) / 100.0
        config.phoneHeightRatioLandscape = CGFloat(modalPhoneLandscapeHeightSlider.value) / 100.0
        config.tabletWidthRatioPortrait = CGFloat(modalTabletPortraitWidthSlider.value) / 100.0
        config.tabletHeightRatioPortrait = CGFloat(modalTabletPortraitHeightSlider.value) / 100.0
        config.tabletWidthRatioLandscape = CGFloat(modalTabletLandscapeWidthSlider.value) / 100.0
        config.tabletHeightRatioLandscape = CGFloat(modalTabletLandscapeHeightSlider.value) / 100.0
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

    // swiftlint:disable:next function_body_length
    @objc func generateCheckoutTapped() {
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
                "id": "test.user",
                "validatedEmail": "test@stash.gg",
                "platform": "IOS"
            ],
            "item": [
                "id": "test-item",
                "name": "Test Purchase",
                "pricePerItem": "0.99",
                "quantity": 1,
                "imageUrl": "https://api.braincloudservers.com/files/portal/g/15152/metadata/products/potion_pack.png",
                "description": "This is a test item purchase."
            ],
            "currency": "USD"
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
                let config = self.buildCardConfig()
                StashNativeCard.sharedInstance().openCard(withURL: checkoutUrl, config: config)
            }
        }.resume()
    }
}
