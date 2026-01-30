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
    private let phoneHeightLabel = UILabel()
    private let phoneHeightSlider = UISlider()
    private let tabletWidthLabel = UILabel()
    private let tabletWidthSlider = UISlider()
    private let tabletHeightLabel = UILabel()
    private let tabletHeightSlider = UISlider()
    
    // Orientation lock state
    private var isLandscapeLocked = false
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupStashPayCard()
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return isLandscapeLocked ? .landscape : .all
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
        
        // Size Configuration Section
        let sizeConfigTitle = UILabel()
        sizeConfigTitle.text = "Card Size Configuration"
        sizeConfigTitle.font = .systemFont(ofSize: 16, weight: .bold)
        advancedOptionsContainer.addArrangedSubview(sizeConfigTitle)
        
        // Phone Height Slider (aligned with Android: 68% default)
        phoneHeightLabel.text = "Phone Height: 68%"
        phoneHeightLabel.font = .systemFont(ofSize: 14)
        phoneHeightLabel.textColor = .secondaryLabel
        advancedOptionsContainer.addArrangedSubview(phoneHeightLabel)
        
        phoneHeightSlider.minimumValue = 10
        phoneHeightSlider.maximumValue = 100
        phoneHeightSlider.value = 68 // Aligned with Android default
        phoneHeightSlider.accessibilityLabel = "Adjust phone card height percentage"
        phoneHeightSlider.addTarget(self, action: #selector(phoneHeightChanged), for: .valueChanged)
        advancedOptionsContainer.addArrangedSubview(phoneHeightSlider)
        
        // Tablet Width Slider
        tabletWidthLabel.text = "Tablet Width: 80%"
        tabletWidthLabel.font = .systemFont(ofSize: 14)
        tabletWidthLabel.textColor = .secondaryLabel
        advancedOptionsContainer.addArrangedSubview(tabletWidthLabel)
        
        tabletWidthSlider.minimumValue = 10
        tabletWidthSlider.maximumValue = 100
        tabletWidthSlider.value = 80
        tabletWidthSlider.accessibilityLabel = "Adjust tablet card width percentage"
        tabletWidthSlider.addTarget(self, action: #selector(tabletWidthChanged), for: .valueChanged)
        advancedOptionsContainer.addArrangedSubview(tabletWidthSlider)
        
        // Tablet Height Slider
        tabletHeightLabel.text = "Tablet Height: 75%"
        tabletHeightLabel.font = .systemFont(ofSize: 14)
        tabletHeightLabel.textColor = .secondaryLabel
        advancedOptionsContainer.addArrangedSubview(tabletHeightLabel)
        
        tabletHeightSlider.minimumValue = 10
        tabletHeightSlider.maximumValue = 100
        tabletHeightSlider.value = 75
        tabletHeightSlider.accessibilityLabel = "Adjust tablet card height percentage"
        tabletHeightSlider.addTarget(self, action: #selector(tabletHeightChanged), for: .valueChanged)
        advancedOptionsContainer.addArrangedSubview(tabletHeightSlider)
        
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
        // Set aligned default (matching Android)
        StashPayCard.sharedInstance().cardHeightRatio = 0.68
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
        
        if isLandscapeLocked {
            // Force landscape orientation
            if #available(iOS 16.0, *) {
                guard let windowScene = view.window?.windowScene else { return }
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
                setNeedsUpdateOfSupportedInterfaceOrientations()
            } else {
                UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            }
            statusLabel.text = "Locked to Landscape"
        } else {
            // Allow all orientations
            if #available(iOS 16.0, *) {
                setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            statusLabel.text = "Orientation Unlocked"
        }
    }
    
    @objc private func phoneHeightChanged() {
        let ratio = CGFloat(phoneHeightSlider.value) / 100.0
        phoneHeightLabel.text = "Phone Height: \(Int(phoneHeightSlider.value))%"
        StashPayCard.sharedInstance().cardHeightRatio = ratio
    }
    
    @objc private func tabletWidthChanged() {
        let ratio = CGFloat(tabletWidthSlider.value) / 100.0
        tabletWidthLabel.text = "Tablet Width: \(Int(tabletWidthSlider.value))%"
        StashPayCard.sharedInstance().tabletWidthRatio = ratio
    }
    
    @objc private func tabletHeightChanged() {
        let ratio = CGFloat(tabletHeightSlider.value) / 100.0
        tabletHeightLabel.text = "Tablet Height: \(Int(tabletHeightSlider.value))%"
        StashPayCard.sharedInstance().tabletHeightRatio = ratio
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
