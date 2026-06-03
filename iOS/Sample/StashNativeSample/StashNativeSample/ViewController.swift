//
//  ViewController.swift
//  StashNativeSample
//
//  StashNativeCard SDK sample with Settings-style layout.
//

import UIKit
import StashNative

class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Properties

    lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.keyboardDismissMode = .onDrag
        table.tableHeaderView = nil
        return table
    }()

    let defaultURL = "https://test.stashpreview.com/"
    let defaultModalURL = "https://checkout.stash.gg/pay/channel-selection"

    let checkoutUrlTextField = UITextField()
    let browserUrlTextField = UITextField()
    let modalUrlTextField = UITextField()
    // Presentation options: two separate expandables under one category
    var isCheckoutAdvancedExpanded = false
    var isModalAdvancedExpanded = false
    let forcePortraitOnCheckoutSwitch = UISwitch()
    let cardAutoCloseSwitch = UISwitch()
    // Maps each percentage slider to the label it updates.
    var sliderLabels: [ObjectIdentifier: UILabel] = [:]
    let phoneCardHeightSlider = UISlider()
    let phoneCardHeightLabel = UILabel()
    let checkoutTabletPortraitWidthSlider = UISlider()
    let checkoutTabletPortraitWidthLabel = UILabel()
    let checkoutTabletPortraitHeightSlider = UISlider()
    let checkoutTabletPortraitHeightLabel = UILabel()
    let checkoutTabletLandscapeWidthSlider = UISlider()
    let checkoutTabletLandscapeWidthLabel = UILabel()
    let checkoutTabletLandscapeHeightSlider = UISlider()
    let checkoutTabletLandscapeHeightLabel = UILabel()
    let checkoutPhoneLandscapeWidthSlider = UISlider()
    let checkoutPhoneLandscapeWidthLabel = UILabel()
    let checkoutPhoneLandscapeHeightSlider = UISlider()
    let checkoutPhoneLandscapeHeightLabel = UILabel()

    // MARK: - Game simulation
    var simulateLandscapeGame = false
    let simulateLandscapeSwitch = UISwitch()

    let modalAllowDismissSwitch = UISwitch()
    let modalAutoCloseSwitch = UISwitch()
    let modalPhonePortraitWidthSlider = UISlider()
    let modalPhonePortraitWidthLabel = UILabel()
    let modalPhonePortraitHeightSlider = UISlider()
    let modalPhonePortraitHeightLabel = UILabel()
    let modalPhoneLandscapeWidthSlider = UISlider()
    let modalPhoneLandscapeWidthLabel = UILabel()
    let modalPhoneLandscapeHeightSlider = UISlider()
    let modalPhoneLandscapeHeightLabel = UILabel()
    let modalTabletPortraitWidthSlider = UISlider()
    let modalTabletPortraitWidthLabel = UILabel()
    let modalTabletPortraitHeightSlider = UISlider()
    let modalTabletPortraitHeightLabel = UILabel()
    let modalTabletLandscapeWidthSlider = UISlider()
    let modalTabletLandscapeWidthLabel = UILabel()
    let modalTabletLandscapeHeightSlider = UISlider()
    let modalTabletLandscapeHeightLabel = UILabel()

    enum Section: Int, CaseIterable {
        case card
        case modal
        case browser
        case presentationOptions
        case checkoutGenerationSettings
        case gameSimulation
    }

    /// Card option rows (when card expandable is expanded).
    enum CheckoutOptionRow: Int, CaseIterable {
        case cardBackgroundHex
        case forcePortraitOnCheckout
        case cardAutoClose
        case phoneCardHeight
        case phoneLandscapeWidth
        case phoneLandscapeHeight
        case tabletPortraitWidth
        case tabletPortraitHeight
        case tabletLandscapeWidth
        case tabletLandscapeHeight
    }
    /// Modal option rows (when modal expandable is expanded).
    enum ModalOptionRow: Int, CaseIterable {
        case modalBackgroundHex
        case allowDismiss
        case modalAutoClose
        case modalPhonePortraitWidth
        case modalPhonePortraitHeight
        case modalPhoneLandscapeWidth
        case modalPhoneLandscapeHeight
        case modalTabletPortraitWidth
        case modalTabletPortraitHeight
        case modalTabletLandscapeWidth
        case modalTabletLandscapeHeight
    }

    // Checkout Generation Settings
    // Demo test-API key for the sample. A real integration generates checkout links on its own
    // backend; the API key never ships in the client.
    private static let defaultStashApiKey = "QtwPBppVziJPg7NAcfH1sbwkwx5DRbYJtezohJvFy4z505D8zNYOtstVVtJvNfxg"
    static let userDefaultsApiKeyKey = "StashApiKey"
    static let userDefaultsCardBackgroundHexKey = "CardBackgroundColorHex"
    static let userDefaultsModalBackgroundHexKey = "ModalBackgroundColorHex"
    var stashApiKey = ViewController.defaultStashApiKey
    var useTestApi = true
    var pendingAlerts: [(String, String)] = []
    var isPresentingQueuedAlert = false
    let apiKeyTextField = UITextField()
    let cardBackgroundColorTextField = UITextField()
    let modalBackgroundColorTextField = UITextField()
    let useTestApiSwitch = UISwitch()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stash iOS"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .always

        setupTextFields()
        setupCheckoutSlidersAndSwitches()
        setupModalSlidersAndSwitches()
        setupGameSimulation()
        setupStashNativeCard()

        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        flushPendingAlertsIfPossible()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        simulateLandscapeGame ? .landscape : .all
    }

    override var shouldAutorotate: Bool { true }

    // MARK: - Setup

    private func configureStandardUrlTextField(_ field: UITextField, text: String) {
        field.placeholder = "URL"
        field.text = text
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.keyboardType = .URL
        field.textAlignment = .right
        field.font = Layout.bodyFont
        field.clearButtonMode = .whileEditing
    }

    func setupTextFields() {
        configureStandardUrlTextField(checkoutUrlTextField, text: defaultURL)
        configureStandardUrlTextField(browserUrlTextField, text: defaultURL)
        configureStandardUrlTextField(modalUrlTextField, text: defaultModalURL)

        apiKeyTextField.placeholder = "API Key"
        if let saved = UserDefaults.standard.string(forKey: ViewController.userDefaultsApiKeyKey), !saved.isEmpty {
            stashApiKey = saved
            apiKeyTextField.text = saved
        } else {
            apiKeyTextField.text = ViewController.defaultStashApiKey
        }
        apiKeyTextField.autocapitalizationType = .none
        apiKeyTextField.autocorrectionType = .no
        apiKeyTextField.textAlignment = .right
        apiKeyTextField.font = Layout.bodyFont
        apiKeyTextField.clearButtonMode = .whileEditing
        apiKeyTextField.addTarget(self, action: #selector(apiKeyEditingDidEnd), for: .editingDidEnd)
        useTestApiSwitch.isOn = true

        func configureHexField(_ field: UITextField, key: String) {
            field.placeholder = "#RRGGBB (optional)"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.keyboardType = .asciiCapable
            field.textAlignment = .right
            field.font = Layout.bodyFont
            field.clearButtonMode = .whileEditing
            if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
                field.text = saved
            }
        }
        configureHexField(cardBackgroundColorTextField, key: ViewController.userDefaultsCardBackgroundHexKey)
        configureHexField(modalBackgroundColorTextField, key: ViewController.userDefaultsModalBackgroundHexKey)
        cardBackgroundColorTextField.addTarget(
            self, action: #selector(cardBackgroundColorEditingDidEnd), for: .editingDidEnd)
        modalBackgroundColorTextField.addTarget(
            self, action: #selector(modalBackgroundColorEditingDidEnd), for: .editingDidEnd)
    }

    @objc func apiKeyEditingDidEnd() {
        let key = apiKeyTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        UserDefaults.standard.set(key.isEmpty ? nil : key, forKey: ViewController.userDefaultsApiKeyKey)
    }

    /// The trimmed key from the field, or the demo key when the field is empty.
    var effectiveApiKey: String {
        let key = apiKeyTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return key.isEmpty ? ViewController.defaultStashApiKey : key
    }

    @objc func cardBackgroundColorEditingDidEnd() {
        let hex = cardBackgroundColorTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        UserDefaults.standard.set(hex.isEmpty ? nil : hex, forKey: ViewController.userDefaultsCardBackgroundHexKey)
    }

    @objc func modalBackgroundColorEditingDidEnd() {
        let hex = modalBackgroundColorTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        UserDefaults.standard.set(hex.isEmpty ? nil : hex, forKey: ViewController.userDefaultsModalBackgroundHexKey)
    }

    func setupStashNativeCard() {
        StashNativeCard.sharedInstance().delegate = self
    }

    deinit {
        // Clears the SDK delegate on teardown.
        if StashNativeCard.sharedInstance().delegate === self {
            StashNativeCard.sharedInstance().delegate = nil
        }
    }

    // MARK: - Helpers

    func makeSliderCellContent(title: String, valueLabel: UILabel, slider: UISlider) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        let topRow = UIStackView()
        topRow.axis = .horizontal
        topRow.distribution = .equalSpacing
        topRow.alignment = .center
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = Layout.bodyFont
        titleLabel.textColor = .label
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.textAlignment = .right
        topRow.addArrangedSubview(titleLabel)
        topRow.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(topRow)
        stack.addArrangedSubview(slider)
        return stack
    }

    func showAlert(title: String, message: String) {
        print("[StashSample] alert queued: \(title) -- \(message)")
        pendingAlerts.append((title, message))
        flushPendingAlertsIfPossible()
    }

    func flushPendingAlertsIfPossible() {
        guard !isPresentingQueuedAlert,
              presentedViewController == nil,
              !pendingAlerts.isEmpty else {
            return
        }
        let (title, message) = pendingAlerts.removeFirst()
        isPresentingQueuedAlert = true
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.isPresentingQueuedAlert = false
            DispatchQueue.main.async {
                self.flushPendingAlertsIfPossible()
            }
        })
        present(alert, animated: true)
    }
}
