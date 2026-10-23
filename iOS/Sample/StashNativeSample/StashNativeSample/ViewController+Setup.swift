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
                        value: ViewController.maximumHeightPosition(defaults.maximumContentHeight),
                        minimum: 0, maximum: ViewController.maximumHeightPosition(1200))
        configureSlider(cardEdgeMarginSlider, label: cardEdgeMarginLabel,
                        value: Float(defaults.edgeMargin), minimum: 0, maximum: 64)
    }

    /// Smallest card width or height the sample offers; matches the Android sample's floor.
    static let minimumContentDimension: Float = 240

    /// Maximum-height slider position for a height. Position 0 is Available and 1 is the 240 pt
    /// floor, so every position is a legal value and VoiceOver's adjustable steps cross from
    /// Available to 240 pt directly; the Android sample maps its SeekBar the same way.
    static func maximumHeightPosition(_ height: CGFloat) -> Float {
        height <= 0 ? 0 : max(1, Float(height) - minimumContentDimension + 1)
    }

    /// Height for a maximum-height slider position; the inverse of `maximumHeightPosition`.
    static func maximumHeight(atPosition position: Float) -> CGFloat {
        position <= 0 ? 0 : CGFloat(position + minimumContentDimension - 1)
    }

    func configureSlider(_ slider: UISlider, label: UILabel, value: Float,
                         minimum: Float = ViewController.minimumContentDimension, maximum: Float = 1200) {
        slider.minimumValue = minimum
        slider.maximumValue = maximum
        slider.value = value
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        sliderLabels[slider] = label
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        sliderValueChanged(slider)
    }
}
