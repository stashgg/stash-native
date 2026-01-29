//
//  ViewController.swift
//  StashPaySample
//
//  Sample view controller demonstrating StashPayCard SDK integration.
//

import UIKit
// StashPay is imported via bridging header

class ViewController: UIViewController {
    
    // MARK: - Properties
    
    private let urlTextField = UITextField()
    private let statusLabel = UILabel()
    private let webViewModeSwitch = UISwitch()
    private let defaultURL = "https://htmlpreview.github.io/?https://raw.githubusercontent.com/stashgg/stash-unity/refs/heads/main/.github/Stash.Popup.Test/index.html"
    
    // Size configuration UI
    private let phoneHeightLabel = UILabel()
    private let phoneHeightSlider = UISlider()
    private let tabletWidthLabel = UILabel()
    private let tabletWidthSlider = UISlider()
    private let tabletHeightLabel = UILabel()
    private let tabletHeightSlider = UISlider()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupStashPayCard()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Title
        let titleLabel = UILabel()
        titleLabel.text = "StashPay SDK Sample"
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        // URL TextField
        urlTextField.placeholder = "Enter checkout URL"
        urlTextField.text = defaultURL
        urlTextField.borderStyle = .roundedRect
        urlTextField.autocapitalizationType = .none
        urlTextField.autocorrectionType = .no
        urlTextField.keyboardType = .URL
        urlTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(urlTextField)
        
        // Web View Mode Toggle
        let webViewModeContainer = UIStackView()
        webViewModeContainer.axis = .horizontal
        webViewModeContainer.alignment = .center
        webViewModeContainer.spacing = 12
        webViewModeContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webViewModeContainer)
        
        let webViewModeLabel = UILabel()
        webViewModeLabel.text = "Use Web View Mode (Safari)"
        webViewModeLabel.font = .systemFont(ofSize: 16)
        webViewModeLabel.textColor = .label
        webViewModeContainer.addArrangedSubview(webViewModeLabel)
        
        webViewModeSwitch.isOn = false
        webViewModeSwitch.addTarget(self, action: #selector(webViewModeToggled), for: .valueChanged)
        webViewModeContainer.addArrangedSubview(webViewModeSwitch)
        
        // Size Configuration Section
        let sizeConfigTitle = UILabel()
        sizeConfigTitle.text = "Card Size Configuration"
        sizeConfigTitle.font = .systemFont(ofSize: 18, weight: .bold)
        sizeConfigTitle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sizeConfigTitle)
        
        // Phone Height Slider
        phoneHeightLabel.text = "Phone Height: 60%"
        phoneHeightLabel.font = .systemFont(ofSize: 14)
        phoneHeightLabel.textColor = .secondaryLabel
        phoneHeightLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(phoneHeightLabel)
        
        phoneHeightSlider.minimumValue = 10
        phoneHeightSlider.maximumValue = 100
        phoneHeightSlider.value = 60
        phoneHeightSlider.addTarget(self, action: #selector(phoneHeightChanged), for: .valueChanged)
        phoneHeightSlider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(phoneHeightSlider)
        
        // Tablet Width Slider
        tabletWidthLabel.text = "Tablet Width: 80%"
        tabletWidthLabel.font = .systemFont(ofSize: 14)
        tabletWidthLabel.textColor = .secondaryLabel
        tabletWidthLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabletWidthLabel)
        
        tabletWidthSlider.minimumValue = 10
        tabletWidthSlider.maximumValue = 100
        tabletWidthSlider.value = 80
        tabletWidthSlider.addTarget(self, action: #selector(tabletWidthChanged), for: .valueChanged)
        tabletWidthSlider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabletWidthSlider)
        
        // Tablet Height Slider
        tabletHeightLabel.text = "Tablet Height: 75%"
        tabletHeightLabel.font = .systemFont(ofSize: 14)
        tabletHeightLabel.textColor = .secondaryLabel
        tabletHeightLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabletHeightLabel)
        
        tabletHeightSlider.minimumValue = 10
        tabletHeightSlider.maximumValue = 100
        tabletHeightSlider.value = 75
        tabletHeightSlider.addTarget(self, action: #selector(tabletHeightChanged), for: .valueChanged)
        tabletHeightSlider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabletHeightSlider)
        
        // Open Checkout Button
        let checkoutButton = UIButton(type: .system)
        checkoutButton.setTitle("Open Checkout", for: .normal)
        checkoutButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        checkoutButton.backgroundColor = .systemBlue
        checkoutButton.setTitleColor(.white, for: .normal)
        checkoutButton.layer.cornerRadius = 8
        checkoutButton.addTarget(self, action: #selector(openCheckoutTapped), for: .touchUpInside)
        checkoutButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(checkoutButton)
        
        // Status Label
        statusLabel.text = "Ready"
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        
        // Layout
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            urlTextField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            urlTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            urlTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            urlTextField.heightAnchor.constraint(equalToConstant: 44),
            
            webViewModeContainer.topAnchor.constraint(equalTo: urlTextField.bottomAnchor, constant: 16),
            webViewModeContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            webViewModeContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            
            // Size Configuration Section
            sizeConfigTitle.topAnchor.constraint(equalTo: webViewModeContainer.bottomAnchor, constant: 24),
            sizeConfigTitle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            
            phoneHeightLabel.topAnchor.constraint(equalTo: sizeConfigTitle.bottomAnchor, constant: 16),
            phoneHeightLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            phoneHeightLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            phoneHeightSlider.topAnchor.constraint(equalTo: phoneHeightLabel.bottomAnchor, constant: 4),
            phoneHeightSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            phoneHeightSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            tabletWidthLabel.topAnchor.constraint(equalTo: phoneHeightSlider.bottomAnchor, constant: 12),
            tabletWidthLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            tabletWidthLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            tabletWidthSlider.topAnchor.constraint(equalTo: tabletWidthLabel.bottomAnchor, constant: 4),
            tabletWidthSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            tabletWidthSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            tabletHeightLabel.topAnchor.constraint(equalTo: tabletWidthSlider.bottomAnchor, constant: 12),
            tabletHeightLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            tabletHeightLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            tabletHeightSlider.topAnchor.constraint(equalTo: tabletHeightLabel.bottomAnchor, constant: 4),
            tabletHeightSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            tabletHeightSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            checkoutButton.topAnchor.constraint(equalTo: tabletHeightSlider.bottomAnchor, constant: 24),
            checkoutButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            checkoutButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            checkoutButton.heightAnchor.constraint(equalToConstant: 50),
            
            statusLabel.topAnchor.constraint(equalTo: checkoutButton.bottomAnchor, constant: 24),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
        
        // Dismiss keyboard on tap
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        view.addGestureRecognizer(tapGesture)
    }
    
    private func setupStashPayCard() {
        StashPayCard.sharedInstance().delegate = self
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
