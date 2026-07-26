//
//  ViewController+Setup.swift
//  StashNativeSample
//
//  Setup and configuration methods for ViewController.
//

import UIKit

// MARK: - Setup

extension ViewController {

    func setupLockLandscape() {
        lockLandscapeSwitch.isOn = false
        lockLandscapeSwitch.addTarget(
            self,
            action: #selector(lockLandscapeToggled(_:)),
            for: .valueChanged
        )
    }

    func setupCheckoutSlidersAndSwitches() {
        forcePortraitOnCheckoutSwitch.isOn = false
        cardAutoCloseSwitch.isOn = true
        configureSlider(phoneCardHeightSlider, label: phoneCardHeightLabel, value: 68)
        configureSlider(checkoutPhoneLandscapeWidthSlider, label: checkoutPhoneLandscapeWidthLabel, value: 70)
        configureSlider(checkoutPhoneLandscapeHeightSlider, label: checkoutPhoneLandscapeHeightLabel, value: 90)
        configureSlider(checkoutTabletPortraitWidthSlider, label: checkoutTabletPortraitWidthLabel, value: 40)
        configureSlider(checkoutTabletPortraitHeightSlider, label: checkoutTabletPortraitHeightLabel, value: 50)
        configureSlider(checkoutTabletLandscapeWidthSlider, label: checkoutTabletLandscapeWidthLabel, value: 30)
        configureSlider(checkoutTabletLandscapeHeightSlider, label: checkoutTabletLandscapeHeightLabel, value: 60)
    }

    func setupModalSlidersAndSwitches() {
        modalAllowDismissSwitch.isOn = true
        modalAutoCloseSwitch.isOn = true
        configureSlider(modalPhonePortraitWidthSlider, label: modalPhonePortraitWidthLabel, value: 80)
        configureSlider(modalPhonePortraitHeightSlider, label: modalPhonePortraitHeightLabel, value: 50)
        configureSlider(modalPhoneLandscapeWidthSlider, label: modalPhoneLandscapeWidthLabel, value: 50)
        configureSlider(modalPhoneLandscapeHeightSlider, label: modalPhoneLandscapeHeightLabel, value: 80)
        configureSlider(modalTabletPortraitWidthSlider, label: modalTabletPortraitWidthLabel, value: 40)
        configureSlider(modalTabletPortraitHeightSlider, label: modalTabletPortraitHeightLabel, value: 30)
        configureSlider(modalTabletLandscapeWidthSlider, label: modalTabletLandscapeWidthLabel, value: 30)
        configureSlider(modalTabletLandscapeHeightSlider, label: modalTabletLandscapeHeightLabel, value: 40)
    }

    func configureSlider(_ slider: UISlider, label: UILabel, value: Float) {
        slider.minimumValue = 10
        slider.maximumValue = 100
        slider.value = value
        label.font = .systemFont(ofSize: 17, weight: .regular)
        label.textColor = .secondaryLabel
        sliderLabels[slider] = label
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        sliderValueChanged(slider)
    }
}
