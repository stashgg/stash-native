//
//  ViewController+Setup.swift
//  StashNativeSample
//
//  Setup and configuration methods for ViewController.
//

import UIKit
import StashNative

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
        let defaults = StashNativeCardConfig()
        cardPreferPortraitSwitch.isOn = defaults.orientationPreference == .portrait
        cardAllowDismissSwitch.isOn = defaults.allowDismiss
        cardAutoCloseSwitch.isOn = defaults.autoClose
        configureSlider(cardPreferredWidthSlider, label: cardPreferredWidthLabel,
                        value: Float(defaults.preferredContentWidth))
        configureSlider(cardPreferredHeightSlider, label: cardPreferredHeightLabel,
                        value: Float(defaults.preferredContentHeight))
        configureSlider(cardMaximumHeightSlider, label: cardMaximumHeightLabel,
                        value: Float(defaults.maximumContentHeight), minimum: 0)
        configureSlider(cardEdgeMarginSlider, label: cardEdgeMarginLabel,
                        value: Float(defaults.edgeMargin), minimum: 0, maximum: 64)
    }

    func configureSlider(_ slider: UISlider, label: UILabel, value: Float,
                         minimum: Float = 240, maximum: Float = 1200) {
        slider.minimumValue = minimum
        slider.maximumValue = maximum
        slider.value = value
        label.font = .systemFont(ofSize: 17, weight: .regular)
        label.textColor = .secondaryLabel
        sliderLabels[slider] = label
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        sliderValueChanged(slider)
    }
}
