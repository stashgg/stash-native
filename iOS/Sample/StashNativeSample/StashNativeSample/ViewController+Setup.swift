//
//  ViewController+Setup.swift
//  StashNativeSample
//
//  Setup and configuration methods for ViewController.
//

import UIKit

// MARK: - Setup

extension ViewController {

    func setupCheckoutSlidersAndSwitches() {
        forcePortraitOnCheckoutSwitch.isOn = false
        forcePortraitOnCheckoutSwitch.addTarget(
            self,
            action: #selector(forcePortraitOnCheckoutToggled(_:)),
            for: .valueChanged
        )
        configureSlider(phoneCardHeightSlider, label: phoneCardHeightLabel, value: 68)
        phoneCardHeightSlider.addTarget(
            self,
            action: #selector(phoneCardHeightChanged),
            for: .valueChanged
        )
        configureSlider(checkoutPhoneLandscapeWidthSlider, label: checkoutPhoneLandscapeWidthLabel, value: 90)
        checkoutPhoneLandscapeWidthSlider.addTarget(
            self,
            action: #selector(checkoutPhoneLandscapeWidthChanged),
            for: .valueChanged
        )
        configureSlider(checkoutPhoneLandscapeHeightSlider, label: checkoutPhoneLandscapeHeightLabel, value: 60)
        checkoutPhoneLandscapeHeightSlider.addTarget(
            self,
            action: #selector(checkoutPhoneLandscapeHeightChanged),
            for: .valueChanged
        )
        configureSlider(checkoutTabletPortraitWidthSlider, label: checkoutTabletPortraitWidthLabel, value: 40)
        checkoutTabletPortraitWidthSlider.addTarget(
            self,
            action: #selector(checkoutTabletPortraitWidthChanged),
            for: .valueChanged
        )
        configureSlider(checkoutTabletPortraitHeightSlider, label: checkoutTabletPortraitHeightLabel, value: 50)
        checkoutTabletPortraitHeightSlider.addTarget(
            self,
            action: #selector(checkoutTabletPortraitHeightChanged),
            for: .valueChanged
        )
        configureSlider(checkoutTabletLandscapeWidthSlider, label: checkoutTabletLandscapeWidthLabel, value: 30)
        checkoutTabletLandscapeWidthSlider.addTarget(
            self,
            action: #selector(checkoutTabletLandscapeWidthChanged),
            for: .valueChanged
        )
        configureSlider(checkoutTabletLandscapeHeightSlider, label: checkoutTabletLandscapeHeightLabel, value: 60)
        checkoutTabletLandscapeHeightSlider.addTarget(
            self,
            action: #selector(checkoutTabletLandscapeHeightChanged),
            for: .valueChanged
        )
    }

    func setupModalSlidersAndSwitches() {
        modalShowDragBarSwitch.isOn = true
        modalAllowDismissSwitch.isOn = true
        configureSlider(modalPhonePortraitWidthSlider, label: modalPhonePortraitWidthLabel, value: 80)
        modalPhonePortraitWidthSlider.addTarget(
            self,
            action: #selector(modalPhonePortraitWidthChanged),
            for: .valueChanged
        )
        configureSlider(modalPhonePortraitHeightSlider, label: modalPhonePortraitHeightLabel, value: 50)
        modalPhonePortraitHeightSlider.addTarget(
            self,
            action: #selector(modalPhonePortraitHeightChanged),
            for: .valueChanged
        )
        configureSlider(modalPhoneLandscapeWidthSlider, label: modalPhoneLandscapeWidthLabel, value: 50)
        modalPhoneLandscapeWidthSlider.addTarget(
            self,
            action: #selector(modalPhoneLandscapeWidthChanged),
            for: .valueChanged
        )
        configureSlider(modalPhoneLandscapeHeightSlider, label: modalPhoneLandscapeHeightLabel, value: 80)
        modalPhoneLandscapeHeightSlider.addTarget(
            self,
            action: #selector(modalPhoneLandscapeHeightChanged),
            for: .valueChanged
        )
        configureSlider(modalTabletPortraitWidthSlider, label: modalTabletPortraitWidthLabel, value: 40)
        modalTabletPortraitWidthSlider.addTarget(
            self,
            action: #selector(modalTabletPortraitWidthChanged),
            for: .valueChanged
        )
        configureSlider(modalTabletPortraitHeightSlider, label: modalTabletPortraitHeightLabel, value: 30)
        modalTabletPortraitHeightSlider.addTarget(
            self,
            action: #selector(modalTabletPortraitHeightChanged),
            for: .valueChanged
        )
        configureSlider(modalTabletLandscapeWidthSlider, label: modalTabletLandscapeWidthLabel, value: 30)
        modalTabletLandscapeWidthSlider.addTarget(
            self,
            action: #selector(modalTabletLandscapeWidthChanged),
            for: .valueChanged
        )
        configureSlider(modalTabletLandscapeHeightSlider, label: modalTabletLandscapeHeightLabel, value: 40)
        modalTabletLandscapeHeightSlider.addTarget(
            self,
            action: #selector(modalTabletLandscapeHeightChanged),
            for: .valueChanged
        )
    }

    func configureSlider(_ slider: UISlider, label: UILabel, value: Float) {
        slider.minimumValue = 10
        slider.maximumValue = 100
        slider.value = value
        label.text = "\(Int(value))%"
        label.font = .systemFont(ofSize: 17, weight: .regular)
        label.textColor = .secondaryLabel
    }
}
