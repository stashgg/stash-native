//
//  ViewController.swift
//  StashPaySample
//
//  Sample view controller demonstrating StashPayCard SDK integration.
//  Features a two-mode interface with essential controls always visible
//  and advanced options in a collapsible section.
//

import UIKit
// StashPay is imported via bridging header

class ViewController: UIViewController {
    
    // MARK: - Properties
    
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let urlTextField = UITextField()
    private let statusLabel = UILabel()
    private let webViewModeSwitch = UISwitch()
    private let defaultURL = "https://htmlpreview.github.io/?https://raw.githubusercontent.com/stashgg/stash-unity/refs/heads/main/.github/Stash.Popup.Test/index.html"
    
    // Advanced options UI
    private let advancedOptionsToggle = UIButton(type: .system)
    private let advancedOptionsContainer = UIStackView()
    private var isAdvancedExpanded = false
    
    // Size configuration UI
    private let landscapeLockSwitch = UISwitch()
    
    // Phone card height (portrait)
    private let phoneCardHeightLabel = UILabel()
    private let phoneCardHeightSlider = UISlider()
    
    // Tablet Portrait sliders
    private let tabletPortraitWidthLabel = UILabel()
    private let tabletPortraitWidthSlider = UISlider()
    private let tabletPortraitHeightLabel = UILabel()
    private let tabletPortraitHeightSlider = UISlider()
    
    // Tablet Landscape sliders
    private let tabletLandscapeWidthLabel = UILabel()
    private let tabletLandscapeWidthSlider = UISlider()
    private let tabletLandscapeHeightLabel = UILabel()
    private let tabletLandscapeHeightSlider = UISlider()
    
    // Orientation lock state
    private var isLandscapeLocked = false
    
    /// How to enforce landscape when "Lock to Landscape Mode" is ON. Used to test popup portrait forcing.
    private enum LandscapeLockApproach: String, CaseIterable {
        case vcMaskOnly = "VC mask only"
        case vcPlusGeometry = "VC + Geometry (iOS 16+)"
        case vcPlusUIDevice = "VC + UIDevice"
        case vcLandscapeLeft = "VC only – Landscape Left"
        case vcLandscapeRight = "VC only – Landscape Right"
        case allCombined = "All combined"
    }
    private var landscapeLockApproach: LandscapeLockApproach = .vcPlusGeometry
    
    private let landscapeApproachButton = UIButton(type: .system)
    private var landscapeApproachContainer: UIStackView?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupStashPayCard()
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        guard isLandscapeLocked else { return .all }
        switch landscapeLockApproach {
        case .vcLandscapeLeft: return .landscapeLeft
        case .vcLandscapeRight: return .landscapeRight
        default: return .landscape
        }
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Setup scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .onDrag
        view.addSubview(scrollView)
        
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        
        // Title
        let titleLabel = UILabel()
        titleLabel.text = "StashPay SDK Sample"
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.accessibilityLabel = "StashPay SDK Sample Application"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        
        // URL TextField
        urlTextField.placeholder = "Enter checkout URL"
        urlTextField.text = defaultURL
        urlTextField.borderStyle = .roundedRect
        urlTextField.autocapitalizationType = .none
        urlTextField.autocorrectionType = .no
        urlTextField.keyboardType = .URL
        urlTextField.accessibilityLabel = "Enter the checkout URL to open"
        urlTextField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(urlTextField)
        
        // Web View Mode Toggle
        let webViewModeContainer = UIStackView()
        webViewModeContainer.axis = .horizontal
        webViewModeContainer.alignment = .center
        webViewModeContainer.spacing = 12
        webViewModeContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(webViewModeContainer)
        
        let webViewModeLabel = UILabel()
        webViewModeLabel.text = "Use Web View Mode (Safari)"
        webViewModeLabel.font = .systemFont(ofSize: 16)
        webViewModeLabel.textColor = .label
        webViewModeContainer.addArrangedSubview(webViewModeLabel)
        
        webViewModeSwitch.isOn = false
        webViewModeSwitch.accessibilityLabel = "Toggle to use Safari instead of native card UI"
        webViewModeSwitch.addTarget(self, action: #selector(webViewModeToggled), for: .valueChanged)
        webViewModeContainer.addArrangedSubview(webViewModeSwitch)
        
        // Open Checkout Button
        let checkoutButton = UIButton(type: .system)
        checkoutButton.setTitle("Open Checkout", for: .normal)
        checkoutButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        checkoutButton.backgroundColor = .systemBlue
        checkoutButton.setTitleColor(.white, for: .normal)
        checkoutButton.layer.cornerRadius = 8
        checkoutButton.accessibilityLabel = "Open the checkout dialog with the specified URL"
        checkoutButton.addTarget(self, action: #selector(openCheckoutTapped), for: .touchUpInside)
        checkoutButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(checkoutButton)
        
        // Status Label
        statusLabel.text = "Ready"
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.accessibilityLabel = "Current status of the checkout operation"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)
        
        // Advanced Options Toggle
        advancedOptionsToggle.setTitle("▶ Advanced Options", for: .normal)
        advancedOptionsToggle.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        advancedOptionsToggle.contentHorizontalAlignment = .left
        advancedOptionsToggle.accessibilityLabel = "Tap to show or hide advanced configuration options"
        advancedOptionsToggle.addTarget(self, action: #selector(advancedOptionsToggleTapped), for: .touchUpInside)
        advancedOptionsToggle.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(advancedOptionsToggle)
        
        // Advanced Options Container
        advancedOptionsContainer.axis = .vertical
        advancedOptionsContainer.spacing = 12
        advancedOptionsContainer.isHidden = true
        advancedOptionsContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(advancedOptionsContainer)
        
        // Landscape Lock Toggle
        let landscapeLockContainer = UIStackView()
        landscapeLockContainer.axis = .horizontal
        landscapeLockContainer.alignment = .center
        landscapeLockContainer.spacing = 12
        
        let landscapeLockLabel = UILabel()
        landscapeLockLabel.text = "Lock to Landscape Mode"
        landscapeLockLabel.font = .systemFont(ofSize: 16)
        landscapeLockLabel.textColor = .label
        landscapeLockContainer.addArrangedSubview(landscapeLockLabel)
        
        landscapeLockSwitch.isOn = false
        landscapeLockSwitch.accessibilityLabel = "Toggle to lock the app to landscape orientation for testing"
        landscapeLockSwitch.addTarget(self, action: #selector(landscapeLockToggled), for: .valueChanged)
        landscapeLockContainer.addArrangedSubview(landscapeLockSwitch)
        
        advancedOptionsContainer.addArrangedSubview(landscapeLockContainer)
        
        // Lock approach selection (visible when landscape lock is ON)
        let landscapeApproachContainer = UIStackView()
        landscapeApproachContainer.axis = .vertical
        landscapeApproachContainer.spacing = 6
        landscapeApproachContainer.isHidden = true
        
        let landscapeApproachLabel = UILabel()
        landscapeApproachLabel.text = "Lock approach"
        landscapeApproachLabel.font = .systemFont(ofSize: 16)
        landscapeApproachLabel.textColor = .label
        landscapeApproachContainer.addArrangedSubview(landscapeApproachLabel)
        
        landscapeApproachButton.setTitle(landscapeLockApproach.rawValue, for: .normal)
        landscapeApproachButton.titleLabel?.font = .systemFont(ofSize: 15)
        landscapeApproachButton.contentHorizontalAlignment = .leading
        landscapeApproachButton.accessibilityLabel = "Select landscape lock approach for testing"
        landscapeApproachButton.addTarget(self, action: #selector(landscapeApproachTapped), for: .touchUpInside)
        landscapeApproachContainer.addArrangedSubview(landscapeApproachButton)
        
        advancedOptionsContainer.addArrangedSubview(landscapeApproachContainer)
        self.landscapeApproachContainer = landscapeApproachContainer
        
        // Phone Card Height (applies to phone card in portrait)
        let phoneCardTitle = UILabel()
        phoneCardTitle.text = "Phone Card Height"
        phoneCardTitle.font = .systemFont(ofSize: 16, weight: .bold)
        advancedOptionsContainer.addArrangedSubview(phoneCardTitle)
        
        phoneCardHeightLabel.font = .systemFont(ofSize: 14)
        phoneCardHeightLabel.textColor = .secondaryLabel
        advancedOptionsContainer.addArrangedSubview(phoneCardHeightLabel)
        
        phoneCardHeightSlider.minimumValue = 10
        phoneCardHeightSlider.maximumValue = 100
        phoneCardHeightSlider.value = 68
        phoneCardHeightLabel.text = "Height: \(Int(phoneCardHeightSlider.value))%"
        phoneCardHeightSlider.accessibilityLabel = "Phone card height percentage"
        phoneCardHeightSlider.addTarget(self, action: #selector(phoneCardHeightChanged), for: .valueChanged)
        advancedOptionsContainer.addArrangedSubview(phoneCardHeightSlider)
        
        // Size Configuration Section - Tablet Portrait
        let tabletPortraitTitle = UILabel()
        tabletPortraitTitle.text = "Tablet Size (Portrait)"
        tabletPortraitTitle.font = .systemFont(ofSize: 16, weight: .bold)
        advancedOptionsContainer.addArrangedSubview(tabletPortraitTitle)
        
        tabletPortraitWidthLabel.font = .systemFont(ofSize: 14)
        tabletPortraitWidthLabel.textColor = .secondaryLabel
        advancedOptionsContainer.addArrangedSubview(tabletPortraitWidthLabel)
        
        tabletPortraitWidthSlider.minimumValue = 10
        tabletPortraitWidthSlider.maximumValue = 100
        tabletPortraitWidthSlider.value = 40
        tabletPortraitWidthLabel.text = "Width: \(Int(tabletPortraitWidthSlider.value))%"
        tabletPortraitWidthSlider.accessibilityLabel = "Tablet portrait width percentage"
        tabletPortraitWidthSlider.addTarget(self, action: #selector(tabletPortraitWidthChanged), for: .valueChanged)
        advancedOptionsContainer.addArrangedSubview(tabletPortraitWidthSlider)
        
        tabletPortraitHeightLabel.font = .systemFont(ofSize: 14)
        tabletPortraitHeightLabel.textColor = .secondaryLabel
        advancedOptionsContainer.addArrangedSubview(tabletPortraitHeightLabel)
        
        tabletPortraitHeightSlider.minimumValue = 10
        tabletPortraitHeightSlider.maximumValue = 100
        tabletPortraitHeightSlider.value = 50
        tabletPortraitHeightLabel.text = "Height: \(Int(tabletPortraitHeightSlider.value))%"
        tabletPortraitHeightSlider.accessibilityLabel = "Tablet portrait height percentage"
        tabletPortraitHeightSlider.addTarget(self, action: #selector(tabletPortraitHeightChanged), for: .valueChanged)
        advancedOptionsContainer.addArrangedSubview(tabletPortraitHeightSlider)
        
        // Size Configuration Section - Tablet Landscape
        let tabletLandscapeTitle = UILabel()
        tabletLandscapeTitle.text = "Tablet Size (Landscape)"
        tabletLandscapeTitle.font = .systemFont(ofSize: 16, weight: .bold)
        advancedOptionsContainer.addArrangedSubview(tabletLandscapeTitle)
        
        tabletLandscapeWidthLabel.font = .systemFont(ofSize: 14)
        tabletLandscapeWidthLabel.textColor = .secondaryLabel
        advancedOptionsContainer.addArrangedSubview(tabletLandscapeWidthLabel)
        
        tabletLandscapeWidthSlider.minimumValue = 10
        tabletLandscapeWidthSlider.maximumValue = 100
        tabletLandscapeWidthSlider.value = 30
        tabletLandscapeWidthLabel.text = "Width: \(Int(tabletLandscapeWidthSlider.value))%"
        tabletLandscapeWidthSlider.accessibilityLabel = "Tablet landscape width percentage"
        tabletLandscapeWidthSlider.addTarget(self, action: #selector(tabletLandscapeWidthChanged), for: .valueChanged)
        advancedOptionsContainer.addArrangedSubview(tabletLandscapeWidthSlider)
        
        tabletLandscapeHeightLabel.font = .systemFont(ofSize: 14)
        tabletLandscapeHeightLabel.textColor = .secondaryLabel
        advancedOptionsContainer.addArrangedSubview(tabletLandscapeHeightLabel)
        
        tabletLandscapeHeightSlider.minimumValue = 10
        tabletLandscapeHeightSlider.maximumValue = 100
        tabletLandscapeHeightSlider.value = 60
        tabletLandscapeHeightLabel.text = "Height: \(Int(tabletLandscapeHeightSlider.value))%"
        tabletLandscapeHeightSlider.accessibilityLabel = "Tablet landscape height percentage"
        tabletLandscapeHeightSlider.addTarget(self, action: #selector(tabletLandscapeHeightChanged), for: .valueChanged)
        advancedOptionsContainer.addArrangedSubview(tabletLandscapeHeightSlider)
        
        // Layout
        NSLayoutConstraint.activate([
            // Scroll view fills the entire safe area
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Content view fills scroll view and matches width
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            // Title
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // URL text field
            urlTextField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            urlTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            urlTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            urlTextField.heightAnchor.constraint(equalToConstant: 44),
            
            // Web View Mode toggle
            webViewModeContainer.topAnchor.constraint(equalTo: urlTextField.bottomAnchor, constant: 16),
            webViewModeContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            webViewModeContainer.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),
            
            // Open Checkout Button
            checkoutButton.topAnchor.constraint(equalTo: webViewModeContainer.bottomAnchor, constant: 20),
            checkoutButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            checkoutButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            checkoutButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Status label
            statusLabel.topAnchor.constraint(equalTo: checkoutButton.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Advanced options toggle
            advancedOptionsToggle.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 24),
            advancedOptionsToggle.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            advancedOptionsToggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Advanced options container
            advancedOptionsContainer.topAnchor.constraint(equalTo: advancedOptionsToggle.bottomAnchor, constant: 12),
            advancedOptionsContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            advancedOptionsContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            advancedOptionsContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40),
        ])
        
        // Dismiss keyboard on tap
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }
    
    private func setupStashPayCard() {
        StashPayCard.sharedInstance().delegate = self
        // Phone card height (portrait)
        StashPayCard.sharedInstance().cardHeightRatioPortrait = CGFloat(phoneCardHeightSlider.value) / 100.0
        // Tablet defaults
        StashPayCard.sharedInstance().tabletWidthRatioPortrait = 0.4
        StashPayCard.sharedInstance().tabletHeightRatioPortrait = 0.5
        StashPayCard.sharedInstance().tabletWidthRatioLandscape = 0.3
        StashPayCard.sharedInstance().tabletHeightRatioLandscape = 0.6
    }
    
    // MARK: - Actions
    
    @objc private func openCheckoutTapped() {
        guard let url = urlTextField.text, !url.isEmpty else {
            showAlert(title: "Error", message: "Please enter a URL")
            return
        }
        
        statusLabel.text = "Opening checkout..."
        StashPayCard.sharedInstance().openCheckout(withURL: url)
    }
    
    @objc private func webViewModeToggled() {
        StashPayCard.sharedInstance().forceWebBasedCheckout = webViewModeSwitch.isOn
        let modeText = webViewModeSwitch.isOn ? "Web View (Safari)" : "Card UI"
        statusLabel.text = "Mode: \(modeText)"
    }
    
    @objc private func advancedOptionsToggleTapped() {
        isAdvancedExpanded = !isAdvancedExpanded
        
        UIView.animate(withDuration: 0.25) {
            self.advancedOptionsContainer.isHidden = !self.isAdvancedExpanded
            self.advancedOptionsToggle.setTitle(
                self.isAdvancedExpanded ? "▼ Advanced Options" : "▶ Advanced Options",
                for: .normal
            )
            self.view.layoutIfNeeded()
        }
    }
    
    @objc private func landscapeLockToggled() {
        isLandscapeLocked = landscapeLockSwitch.isOn
        landscapeApproachContainer?.isHidden = !isLandscapeLocked
        
        if isLandscapeLocked {
            applyLandscapeLockApproach()
            statusLabel.text = "Locked to Landscape (\(landscapeLockApproach.rawValue))"
        } else {
            if #available(iOS 16.0, *) {
                setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            statusLabel.text = "Orientation Unlocked"
        }
    }
    
    @objc private func landscapeApproachTapped() {
        let sheet = UIAlertController(title: "Lock approach", message: "Choose how to enforce landscape for testing popup portrait forcing.", preferredStyle: .actionSheet)
        for approach in LandscapeLockApproach.allCases {
            sheet.addAction(UIAlertAction(title: approach.rawValue, style: .default) { [weak self] _ in
                self?.landscapeLockApproach = approach
                self?.landscapeApproachButton.setTitle(approach.rawValue, for: .normal)
                if self?.isLandscapeLocked == true {
                    self?.applyLandscapeLockApproach()
                    self?.statusLabel.text = "Locked to Landscape (\(approach.rawValue))"
                }
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = landscapeApproachButton
            popover.sourceRect = landscapeApproachButton.bounds
        }
        present(sheet, animated: true)
    }
    
    private func applyLandscapeLockApproach() {
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        
        switch landscapeLockApproach {
        case .vcMaskOnly:
            break
        case .vcPlusGeometry:
            if #available(iOS 16.0, *) {
                guard let windowScene = view.window?.windowScene else { return }
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
            }
        case .vcPlusUIDevice:
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        case .vcLandscapeLeft:
            break
        case .vcLandscapeRight:
            break
        case .allCombined:
            if #available(iOS 16.0, *) {
                guard let windowScene = view.window?.windowScene else { return }
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
            }
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        }
    }
    
    @objc private func phoneCardHeightChanged() {
        let ratio = CGFloat(phoneCardHeightSlider.value) / 100.0
        phoneCardHeightLabel.text = "Height: \(Int(phoneCardHeightSlider.value))%"
        StashPayCard.sharedInstance().cardHeightRatioPortrait = ratio
    }
    
    @objc private func tabletPortraitWidthChanged() {
        let ratio = CGFloat(tabletPortraitWidthSlider.value) / 100.0
        tabletPortraitWidthLabel.text = "Width: \(Int(tabletPortraitWidthSlider.value))%"
        StashPayCard.sharedInstance().tabletWidthRatioPortrait = ratio
    }
    
    @objc private func tabletPortraitHeightChanged() {
        let ratio = CGFloat(tabletPortraitHeightSlider.value) / 100.0
        tabletPortraitHeightLabel.text = "Height: \(Int(tabletPortraitHeightSlider.value))%"
        StashPayCard.sharedInstance().tabletHeightRatioPortrait = ratio
    }
    
    @objc private func tabletLandscapeWidthChanged() {
        let ratio = CGFloat(tabletLandscapeWidthSlider.value) / 100.0
        tabletLandscapeWidthLabel.text = "Width: \(Int(tabletLandscapeWidthSlider.value))%"
        StashPayCard.sharedInstance().tabletWidthRatioLandscape = ratio
    }
    
    @objc private func tabletLandscapeHeightChanged() {
        let ratio = CGFloat(tabletLandscapeHeightSlider.value) / 100.0
        tabletLandscapeHeightLabel.text = "Height: \(Int(tabletLandscapeHeightSlider.value))%"
        StashPayCard.sharedInstance().tabletHeightRatioLandscape = ratio
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - StashPayCardDelegate

extension ViewController: StashPayCardDelegate {
    
    func stashPayCardDidCompletePayment() {
        print("Payment successful")
        DispatchQueue.main.async {
            self.statusLabel.text = "Payment Success"
            self.showAlert(title: "Success", message: "Payment completed successfully")
        }
    }
    
    func stashPayCardDidFailPayment() {
        print("Payment failed")
        DispatchQueue.main.async {
            self.statusLabel.text = "Payment Failed"
            self.showAlert(title: "Failed", message: "Payment failed")
        }
    }
    
    func stashPayCardDidDismiss() {
        print("Dialog dismissed")
        DispatchQueue.main.async {
            self.statusLabel.text = "Dialog dismissed"
        }
    }
    
    func stashPayCardDidReceiveOpt(in optinType: String) {
        print("Opt-in response: \(optinType)")
        DispatchQueue.main.async {
            self.statusLabel.text = "Opt-in: \(optinType)"
        }
    }
    
    func stashPayCardDidLoadPage(_ loadTimeMs: Double) {
        print("Page loaded in \(loadTimeMs)ms")
    }
}
