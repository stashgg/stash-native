//
//  ViewController.swift
//  StashPaySample
//
//  Sample view controller demonstrating StashPayCard SDK integration.
//  Features separate sections for Checkout and Modal with their own advanced options.
//

import UIKit
// StashPay is imported via bridging header

class ViewController: UIViewController {
    
    // MARK: - Properties
    
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let defaultURL = "https://htmlpreview.github.io/?https://raw.githubusercontent.com/stashgg/stash-unity/refs/heads/main/.github/Stash.Popup.Test/index.html"
    
    // URL inputs
    private let checkoutUrlTextField = UITextField()
    private let modalUrlTextField = UITextField()
    private let statusLabel = UILabel()
    
    // Advanced options - Checkout
    private let advancedCheckoutToggle = UIButton(type: .system)
    private let advancedCheckoutContainer = UIStackView()
    private let advancedCheckoutSection = UIStackView()
    private var isCheckoutAdvancedExpanded = false
    
    private let webViewModeSwitch = UISwitch()
    private let landscapeLockSwitch = UISwitch()
    private let phoneCardHeightSlider = UISlider()
    private let phoneCardHeightLabel = UILabel()
    private let checkoutTabletPortraitWidthSlider = UISlider()
    private let checkoutTabletPortraitWidthLabel = UILabel()
    private let checkoutTabletPortraitHeightSlider = UISlider()
    private let checkoutTabletPortraitHeightLabel = UILabel()
    private let checkoutTabletLandscapeWidthSlider = UISlider()
    private let checkoutTabletLandscapeWidthLabel = UILabel()
    private let checkoutTabletLandscapeHeightSlider = UISlider()
    private let checkoutTabletLandscapeHeightLabel = UILabel()
    
    // Advanced options - Modal
    private let advancedModalToggle = UIButton(type: .system)
    private let advancedModalContainer = UIStackView()
    private let advancedModalSection = UIStackView()
    private var isModalAdvancedExpanded = false
    
    private let modalShowDragBarSwitch = UISwitch()
    private let modalAllowDismissSwitch = UISwitch()
    private let modalPhonePortraitWidthSlider = UISlider()
    private let modalPhonePortraitWidthLabel = UILabel()
    private let modalPhonePortraitHeightSlider = UISlider()
    private let modalPhonePortraitHeightLabel = UILabel()
    private let modalPhoneLandscapeWidthSlider = UISlider()
    private let modalPhoneLandscapeWidthLabel = UILabel()
    private let modalPhoneLandscapeHeightSlider = UISlider()
    private let modalPhoneLandscapeHeightLabel = UILabel()
    private let modalTabletPortraitWidthSlider = UISlider()
    private let modalTabletPortraitWidthLabel = UILabel()
    private let modalTabletPortraitHeightSlider = UISlider()
    private let modalTabletPortraitHeightLabel = UILabel()
    private let modalTabletLandscapeWidthSlider = UISlider()
    private let modalTabletLandscapeWidthLabel = UILabel()
    private let modalTabletLandscapeHeightSlider = UISlider()
    private let modalTabletLandscapeHeightLabel = UILabel()
    
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
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        
        // ==================== CHECKOUT SECTION ====================
        
        let checkoutSectionLabel = createSectionLabel("Checkout")
        contentView.addSubview(checkoutSectionLabel)
        
        setupTextField(checkoutUrlTextField, placeholder: "Checkout URL")
        contentView.addSubview(checkoutUrlTextField)
        
        let checkoutButton = createButton(title: "Open Checkout", filled: true)
        checkoutButton.addTarget(self, action: #selector(openCheckoutTapped), for: .touchUpInside)
        contentView.addSubview(checkoutButton)
        
        // ==================== MODAL SECTION ====================
        
        let modalSectionLabel = createSectionLabel("Modal")
        contentView.addSubview(modalSectionLabel)
        
        setupTextField(modalUrlTextField, placeholder: "Modal URL")
        contentView.addSubview(modalUrlTextField)
        
        let modalButton = createButton(title: "Open Modal", filled: false)
        modalButton.addTarget(self, action: #selector(openModalTapped), for: .touchUpInside)
        contentView.addSubview(modalButton)
        
        // ==================== STATUS ====================
        
        statusLabel.text = "Ready"
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)
        
        // ==================== ADVANCED OPTIONS - CHECKOUT ====================
        
        advancedCheckoutToggle.setTitle("▶ Advanced Options - Checkout", for: .normal)
        advancedCheckoutToggle.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        advancedCheckoutToggle.contentHorizontalAlignment = .left
        advancedCheckoutToggle.addTarget(self, action: #selector(advancedCheckoutToggleTapped), for: .touchUpInside)
        
        setupAdvancedCheckoutContainer()
        
        advancedCheckoutSection.axis = .vertical
        advancedCheckoutSection.spacing = 8
        advancedCheckoutSection.translatesAutoresizingMaskIntoConstraints = false
        advancedCheckoutSection.addArrangedSubview(advancedCheckoutToggle)
        advancedCheckoutSection.addArrangedSubview(advancedCheckoutContainer)
        contentView.addSubview(advancedCheckoutSection)
        
        // ==================== ADVANCED OPTIONS - MODAL ====================
        
        advancedModalToggle.setTitle("▶ Advanced Options - Modal", for: .normal)
        advancedModalToggle.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        advancedModalToggle.contentHorizontalAlignment = .left
        advancedModalToggle.addTarget(self, action: #selector(advancedModalToggleTapped), for: .touchUpInside)
        
        setupAdvancedModalContainer()
        
        advancedModalSection.axis = .vertical
        advancedModalSection.spacing = 8
        advancedModalSection.translatesAutoresizingMaskIntoConstraints = false
        advancedModalSection.addArrangedSubview(advancedModalToggle)
        advancedModalSection.addArrangedSubview(advancedModalContainer)
        contentView.addSubview(advancedModalSection)
        
        // ==================== LAYOUT ====================
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Checkout section
            checkoutSectionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            checkoutSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            checkoutUrlTextField.topAnchor.constraint(equalTo: checkoutSectionLabel.bottomAnchor, constant: 8),
            checkoutUrlTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            checkoutUrlTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            checkoutUrlTextField.heightAnchor.constraint(equalToConstant: 44),
            
            checkoutButton.topAnchor.constraint(equalTo: checkoutUrlTextField.bottomAnchor, constant: 12),
            checkoutButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            checkoutButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            checkoutButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Modal section
            modalSectionLabel.topAnchor.constraint(equalTo: checkoutButton.bottomAnchor, constant: 24),
            modalSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            modalUrlTextField.topAnchor.constraint(equalTo: modalSectionLabel.bottomAnchor, constant: 8),
            modalUrlTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            modalUrlTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            modalUrlTextField.heightAnchor.constraint(equalToConstant: 44),
            
            modalButton.topAnchor.constraint(equalTo: modalUrlTextField.bottomAnchor, constant: 12),
            modalButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            modalButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            modalButton.heightAnchor.constraint(equalToConstant: 50),
            
            // Status
            statusLabel.topAnchor.constraint(equalTo: modalButton.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Advanced Checkout Section
            advancedCheckoutSection.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 24),
            advancedCheckoutSection.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            advancedCheckoutSection.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            // Advanced Modal Section
            advancedModalSection.topAnchor.constraint(equalTo: advancedCheckoutSection.bottomAnchor, constant: 12),
            advancedModalSection.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            advancedModalSection.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            advancedModalSection.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40),
        ])
        
        // Dismiss keyboard on tap
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }
    
    private func setupAdvancedCheckoutContainer() {
        advancedCheckoutContainer.axis = .vertical
        advancedCheckoutContainer.spacing = 12
        advancedCheckoutContainer.isHidden = true
        
        // Web View Mode
        let webViewRow = createSwitchRow("Use Web View Mode (Safari)", switchView: webViewModeSwitch)
        webViewModeSwitch.addTarget(self, action: #selector(webViewModeToggled), for: .valueChanged)
        advancedCheckoutContainer.addArrangedSubview(webViewRow)
        
        // Landscape Lock
        let landscapeRow = createSwitchRow("Lock to Landscape Mode", switchView: landscapeLockSwitch)
        landscapeLockSwitch.addTarget(self, action: #selector(landscapeLockToggled), for: .valueChanged)
        advancedCheckoutContainer.addArrangedSubview(landscapeRow)
        
        // Phone Card Height
        advancedCheckoutContainer.addArrangedSubview(createBoldLabel("Phone Card Height"))
        phoneCardHeightSlider.minimumValue = 10
        phoneCardHeightSlider.maximumValue = 100
        phoneCardHeightSlider.value = 68
        phoneCardHeightLabel.text = "Height: 68%"
        phoneCardHeightSlider.addTarget(self, action: #selector(phoneCardHeightChanged), for: .valueChanged)
        advancedCheckoutContainer.addArrangedSubview(phoneCardHeightLabel)
        advancedCheckoutContainer.addArrangedSubview(phoneCardHeightSlider)
        
        // Checkout Tablet Portrait
        advancedCheckoutContainer.addArrangedSubview(createBoldLabel("Tablet Size (Portrait)"))
        checkoutTabletPortraitWidthSlider.minimumValue = 10
        checkoutTabletPortraitWidthSlider.maximumValue = 100
        checkoutTabletPortraitWidthSlider.value = 40
        checkoutTabletPortraitWidthLabel.text = "Width: 40%"
        checkoutTabletPortraitWidthSlider.addTarget(self, action: #selector(checkoutTabletPortraitWidthChanged), for: .valueChanged)
        advancedCheckoutContainer.addArrangedSubview(checkoutTabletPortraitWidthLabel)
        advancedCheckoutContainer.addArrangedSubview(checkoutTabletPortraitWidthSlider)
        
        checkoutTabletPortraitHeightSlider.minimumValue = 10
        checkoutTabletPortraitHeightSlider.maximumValue = 100
        checkoutTabletPortraitHeightSlider.value = 50
        checkoutTabletPortraitHeightLabel.text = "Height: 50%"
        checkoutTabletPortraitHeightSlider.addTarget(self, action: #selector(checkoutTabletPortraitHeightChanged), for: .valueChanged)
        advancedCheckoutContainer.addArrangedSubview(checkoutTabletPortraitHeightLabel)
        advancedCheckoutContainer.addArrangedSubview(checkoutTabletPortraitHeightSlider)
        
        // Checkout Tablet Landscape
        advancedCheckoutContainer.addArrangedSubview(createBoldLabel("Tablet Size (Landscape)"))
        checkoutTabletLandscapeWidthSlider.minimumValue = 10
        checkoutTabletLandscapeWidthSlider.maximumValue = 100
        checkoutTabletLandscapeWidthSlider.value = 30
        checkoutTabletLandscapeWidthLabel.text = "Width: 30%"
        checkoutTabletLandscapeWidthSlider.addTarget(self, action: #selector(checkoutTabletLandscapeWidthChanged), for: .valueChanged)
        advancedCheckoutContainer.addArrangedSubview(checkoutTabletLandscapeWidthLabel)
        advancedCheckoutContainer.addArrangedSubview(checkoutTabletLandscapeWidthSlider)
        
        checkoutTabletLandscapeHeightSlider.minimumValue = 10
        checkoutTabletLandscapeHeightSlider.maximumValue = 100
        checkoutTabletLandscapeHeightSlider.value = 60
        checkoutTabletLandscapeHeightLabel.text = "Height: 60%"
        checkoutTabletLandscapeHeightSlider.addTarget(self, action: #selector(checkoutTabletLandscapeHeightChanged), for: .valueChanged)
        advancedCheckoutContainer.addArrangedSubview(checkoutTabletLandscapeHeightLabel)
        advancedCheckoutContainer.addArrangedSubview(checkoutTabletLandscapeHeightSlider)
    }
    
    private func setupAdvancedModalContainer() {
        advancedModalContainer.axis = .vertical
        advancedModalContainer.spacing = 12
        advancedModalContainer.isHidden = true
        
        // Modal behavior switches
        modalShowDragBarSwitch.isOn = true
        let showDragBarRow = createSwitchRow("Show Drag Bar", switchView: modalShowDragBarSwitch)
        advancedModalContainer.addArrangedSubview(showDragBarRow)
        
        modalAllowDismissSwitch.isOn = true
        let allowDismissRow = createSwitchRow("Allow Dismiss (tap outside)", switchView: modalAllowDismissSwitch)
        advancedModalContainer.addArrangedSubview(allowDismissRow)
        
        // Modal Phone Portrait
        advancedModalContainer.addArrangedSubview(createBoldLabel("Phone Size (Portrait)"))
        setupSlider(modalPhonePortraitWidthSlider, value: 90, label: modalPhonePortraitWidthLabel, prefix: "Width")
        advancedModalContainer.addArrangedSubview(modalPhonePortraitWidthLabel)
        advancedModalContainer.addArrangedSubview(modalPhonePortraitWidthSlider)
        
        setupSlider(modalPhonePortraitHeightSlider, value: 70, label: modalPhonePortraitHeightLabel, prefix: "Height")
        advancedModalContainer.addArrangedSubview(modalPhonePortraitHeightLabel)
        advancedModalContainer.addArrangedSubview(modalPhonePortraitHeightSlider)
        
        // Modal Phone Landscape
        advancedModalContainer.addArrangedSubview(createBoldLabel("Phone Size (Landscape)"))
        setupSlider(modalPhoneLandscapeWidthSlider, value: 70, label: modalPhoneLandscapeWidthLabel, prefix: "Width")
        advancedModalContainer.addArrangedSubview(modalPhoneLandscapeWidthLabel)
        advancedModalContainer.addArrangedSubview(modalPhoneLandscapeWidthSlider)
        
        setupSlider(modalPhoneLandscapeHeightSlider, value: 85, label: modalPhoneLandscapeHeightLabel, prefix: "Height")
        advancedModalContainer.addArrangedSubview(modalPhoneLandscapeHeightLabel)
        advancedModalContainer.addArrangedSubview(modalPhoneLandscapeHeightSlider)
        
        // Modal Tablet Portrait
        advancedModalContainer.addArrangedSubview(createBoldLabel("Tablet Size (Portrait)"))
        setupSlider(modalTabletPortraitWidthSlider, value: 60, label: modalTabletPortraitWidthLabel, prefix: "Width")
        advancedModalContainer.addArrangedSubview(modalTabletPortraitWidthLabel)
        advancedModalContainer.addArrangedSubview(modalTabletPortraitWidthSlider)
        
        setupSlider(modalTabletPortraitHeightSlider, value: 70, label: modalTabletPortraitHeightLabel, prefix: "Height")
        advancedModalContainer.addArrangedSubview(modalTabletPortraitHeightLabel)
        advancedModalContainer.addArrangedSubview(modalTabletPortraitHeightSlider)
        
        // Modal Tablet Landscape
        advancedModalContainer.addArrangedSubview(createBoldLabel("Tablet Size (Landscape)"))
        setupSlider(modalTabletLandscapeWidthSlider, value: 50, label: modalTabletLandscapeWidthLabel, prefix: "Width")
        advancedModalContainer.addArrangedSubview(modalTabletLandscapeWidthLabel)
        advancedModalContainer.addArrangedSubview(modalTabletLandscapeWidthSlider)
        
        setupSlider(modalTabletLandscapeHeightSlider, value: 80, label: modalTabletLandscapeHeightLabel, prefix: "Height")
        advancedModalContainer.addArrangedSubview(modalTabletLandscapeHeightLabel)
        advancedModalContainer.addArrangedSubview(modalTabletLandscapeHeightSlider)
    }
    
    private func setupStashPayCard() {
        StashPayCard.sharedInstance().delegate = self
        StashPayCard.sharedInstance().cardHeightRatioPortrait = CGFloat(phoneCardHeightSlider.value) / 100.0
        StashPayCard.sharedInstance().tabletWidthRatioPortrait = CGFloat(checkoutTabletPortraitWidthSlider.value) / 100.0
        StashPayCard.sharedInstance().tabletHeightRatioPortrait = CGFloat(checkoutTabletPortraitHeightSlider.value) / 100.0
        StashPayCard.sharedInstance().tabletWidthRatioLandscape = CGFloat(checkoutTabletLandscapeWidthSlider.value) / 100.0
        StashPayCard.sharedInstance().tabletHeightRatioLandscape = CGFloat(checkoutTabletLandscapeHeightSlider.value) / 100.0
    }
    
    // MARK: - Helper Methods
    
    private func createSectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private func setupTextField(_ textField: UITextField, placeholder: String) {
        textField.placeholder = placeholder
        textField.text = defaultURL
        textField.borderStyle = .roundedRect
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.keyboardType = .URL
        textField.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func createButton(title: String, filled: Bool) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        if filled {
            button.backgroundColor = .systemBlue
            button.setTitleColor(.white, for: .normal)
        } else {
            button.backgroundColor = .clear
            button.setTitleColor(.systemBlue, for: .normal)
            button.layer.borderWidth = 1
            button.layer.borderColor = UIColor.systemBlue.cgColor
        }
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
    
    private func createSwitchRow(_ text: String, switchView: UISwitch) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 16)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(switchView)
        
        return stack
    }
    
    private func createBoldLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14, weight: .bold)
        return label
    }
    
    private func setupSlider(_ slider: UISlider, value: Float, label: UILabel, prefix: String) {
        slider.minimumValue = 10
        slider.maximumValue = 100
        slider.value = value
        label.text = "\(prefix): \(Int(value))%"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
    }
    
    // MARK: - Actions
    
    @objc private func openCheckoutTapped() {
        guard let url = checkoutUrlTextField.text, !url.isEmpty else {
            showAlert(title: "Error", message: "Please enter a checkout URL")
            return
        }
        statusLabel.text = "Opening checkout..."
        StashPayCard.sharedInstance().openCheckout(withURL: url)
    }
    
    @objc private func openModalTapped() {
        guard let url = modalUrlTextField.text, !url.isEmpty else {
            showAlert(title: "Error", message: "Please enter a modal URL")
            return
        }
        statusLabel.text = "Opening modal..."
        let config = buildModalConfig()
        StashPayCard.sharedInstance().openModal(withURL: url, config: config)
    }
    
    private func buildModalConfig() -> StashPayModalConfig {
        let config = StashPayModalConfig()
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
    
    @objc private func webViewModeToggled() {
        StashPayCard.sharedInstance().forceWebBasedCheckout = webViewModeSwitch.isOn
        statusLabel.text = "Mode: \(webViewModeSwitch.isOn ? "Web View (Safari)" : "Card UI")"
    }
    
    @objc private func landscapeLockToggled() {
        isLandscapeLocked = landscapeLockSwitch.isOn
        if isLandscapeLocked {
            if #available(iOS 16.0, *) {
                setNeedsUpdateOfSupportedInterfaceOrientations()
                guard let windowScene = view.window?.windowScene else { return }
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
            }
            statusLabel.text = "Locked to Landscape"
        } else {
            if #available(iOS 16.0, *) {
                setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            statusLabel.text = "Orientation Unlocked"
        }
    }
    
    @objc private func advancedCheckoutToggleTapped() {
        isCheckoutAdvancedExpanded = !isCheckoutAdvancedExpanded
        UIView.animate(withDuration: 0.25) {
            self.advancedCheckoutContainer.isHidden = !self.isCheckoutAdvancedExpanded
            self.advancedCheckoutToggle.setTitle(
                self.isCheckoutAdvancedExpanded ? "▼ Advanced Options - Checkout" : "▶ Advanced Options - Checkout",
                for: .normal
            )
            self.view.layoutIfNeeded()
        }
    }
    
    @objc private func advancedModalToggleTapped() {
        isModalAdvancedExpanded = !isModalAdvancedExpanded
        UIView.animate(withDuration: 0.25) {
            self.advancedModalContainer.isHidden = !self.isModalAdvancedExpanded
            self.advancedModalToggle.setTitle(
                self.isModalAdvancedExpanded ? "▼ Advanced Options - Modal" : "▶ Advanced Options - Modal",
                for: .normal
            )
            self.view.layoutIfNeeded()
        }
    }
    
    // Checkout slider handlers
    @objc private func phoneCardHeightChanged() {
        phoneCardHeightLabel.text = "Height: \(Int(phoneCardHeightSlider.value))%"
        StashPayCard.sharedInstance().cardHeightRatioPortrait = CGFloat(phoneCardHeightSlider.value) / 100.0
    }
    
    @objc private func checkoutTabletPortraitWidthChanged() {
        checkoutTabletPortraitWidthLabel.text = "Width: \(Int(checkoutTabletPortraitWidthSlider.value))%"
        StashPayCard.sharedInstance().tabletWidthRatioPortrait = CGFloat(checkoutTabletPortraitWidthSlider.value) / 100.0
    }
    
    @objc private func checkoutTabletPortraitHeightChanged() {
        checkoutTabletPortraitHeightLabel.text = "Height: \(Int(checkoutTabletPortraitHeightSlider.value))%"
        StashPayCard.sharedInstance().tabletHeightRatioPortrait = CGFloat(checkoutTabletPortraitHeightSlider.value) / 100.0
    }
    
    @objc private func checkoutTabletLandscapeWidthChanged() {
        checkoutTabletLandscapeWidthLabel.text = "Width: \(Int(checkoutTabletLandscapeWidthSlider.value))%"
        StashPayCard.sharedInstance().tabletWidthRatioLandscape = CGFloat(checkoutTabletLandscapeWidthSlider.value) / 100.0
    }
    
    @objc private func checkoutTabletLandscapeHeightChanged() {
        checkoutTabletLandscapeHeightLabel.text = "Height: \(Int(checkoutTabletLandscapeHeightSlider.value))%"
        StashPayCard.sharedInstance().tabletHeightRatioLandscape = CGFloat(checkoutTabletLandscapeHeightSlider.value) / 100.0
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
