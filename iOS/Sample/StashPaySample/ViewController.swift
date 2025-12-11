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
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            urlTextField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),
            urlTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            urlTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            urlTextField.heightAnchor.constraint(equalToConstant: 44),
            
            webViewModeContainer.topAnchor.constraint(equalTo: urlTextField.bottomAnchor, constant: 20),
            webViewModeContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            webViewModeContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            
            checkoutButton.topAnchor.constraint(equalTo: webViewModeContainer.bottomAnchor, constant: 24),
            checkoutButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            checkoutButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            checkoutButton.heightAnchor.constraint(equalToConstant: 50),
            
            statusLabel.topAnchor.constraint(equalTo: checkoutButton.bottomAnchor, constant: 40),
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
