//
//  ViewController.swift
//  StashPaySample
//
//  Sample view controller demonstrating StashPayCard SDK integration.
//  Designed to match Apple’s Human Interface Guidelines and Settings-style layout.
//

import UIKit
// StashPay is imported via bridging header

class ViewController: UIViewController {
    
    // MARK: - Properties
    
    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.keyboardDismissMode = .onDrag
        table.tableHeaderView = nil
        return table
    }()
    
    private let defaultURL = "https://htmlpreview.github.io/?https://raw.githubusercontent.com/stashgg/stash-unity/refs/heads/main/.github/Stash.Popup.Test/index.html"
    
    private let checkoutUrlTextField = UITextField()
    private let modalUrlTextField = UITextField()
    // Presentation options: two separate expandables under one category
    private var isCheckoutAdvancedExpanded = false
    private var isModalAdvancedExpanded = false
    private let webViewModeSwitch = UISwitch()
    private let forcePortraitOnCheckoutSwitch = UISwitch()
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
    private let checkoutPhoneLandscapeWidthSlider = UISlider()
    private let checkoutPhoneLandscapeWidthLabel = UILabel()
    private let checkoutPhoneLandscapeHeightSlider = UISlider()
    private let checkoutPhoneLandscapeHeightLabel = UILabel()
    
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
    
    private enum Section: Int, CaseIterable {
        case checkout
        case modal
        case presentationOptions
        case checkoutGenerationSettings
    }
    
    /// Checkout option rows (when checkout expandable is expanded).
    private enum CheckoutOptionRow: Int, CaseIterable {
        case webViewMode
        case forcePortraitOnCheckout
        case phoneCardHeight
        case phoneLandscapeWidth
        case phoneLandscapeHeight
        case tabletPortraitWidth
        case tabletPortraitHeight
        case tabletLandscapeWidth
        case tabletLandscapeHeight
    }
    /// Modal option rows (when modal expandable is expanded).
    private enum ModalOptionRow: Int, CaseIterable {
        case showDragBar
        case allowDismiss
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
    private static let defaultStashApiKey = "QtwPBppVziJPg7NAcfH1sbwkwx5DRbYJtezohJvFy4z505D8zNYOtstVVtJvNfxg"
    private static let userDefaultsApiKeyKey = "StashApiKey"
    private var stashApiKey = ViewController.defaultStashApiKey
    private var useTestApi = true
    private let apiKeyTextField = UITextField()
    private let useTestApiSwitch = UISwitch()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stash SDK Sample"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .always
        
        setupTextFields()
        setupCheckoutSlidersAndSwitches()
        setupModalSlidersAndSwitches()
        setupStashPayCard()
        
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if navigationController == nil {
            navigationController?.navigationBar.prefersLargeTitles = true
        }
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    // MARK: - Setup
    
    private func setupTextFields() {
        checkoutUrlTextField.placeholder = "URL"
        checkoutUrlTextField.text = defaultURL
        checkoutUrlTextField.autocapitalizationType = .none
        checkoutUrlTextField.autocorrectionType = .no
        checkoutUrlTextField.keyboardType = .URL
        checkoutUrlTextField.textAlignment = .right
        checkoutUrlTextField.font = .systemFont(ofSize: 17, weight: .regular)
        checkoutUrlTextField.clearButtonMode = .whileEditing
        
        modalUrlTextField.placeholder = "URL"
        modalUrlTextField.text = defaultURL
        modalUrlTextField.autocapitalizationType = .none
        modalUrlTextField.autocorrectionType = .no
        modalUrlTextField.keyboardType = .URL
        modalUrlTextField.textAlignment = .right
        modalUrlTextField.font = .systemFont(ofSize: 17, weight: .regular)
        modalUrlTextField.clearButtonMode = .whileEditing
        
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
        apiKeyTextField.font = .systemFont(ofSize: 17, weight: .regular)
        apiKeyTextField.clearButtonMode = .whileEditing
        apiKeyTextField.addTarget(self, action: #selector(apiKeyEditingDidEnd), for: .editingDidEnd)
        useTestApiSwitch.isOn = true
    }
    
    @objc private func apiKeyEditingDidEnd() {
        let key = apiKeyTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        UserDefaults.standard.set(key.isEmpty ? nil : key, forKey: ViewController.userDefaultsApiKeyKey)
    }
    
    private func setupCheckoutSlidersAndSwitches() {
        webViewModeSwitch.addTarget(self, action: #selector(webViewModeToggled), for: .valueChanged)
        forcePortraitOnCheckoutSwitch.isOn = false
        forcePortraitOnCheckoutSwitch.addTarget(self, action: #selector(forcePortraitOnCheckoutToggled), for: .valueChanged)
        configureSlider(phoneCardHeightSlider, label: phoneCardHeightLabel, value: 68)
        phoneCardHeightSlider.addTarget(self, action: #selector(phoneCardHeightChanged), for: .valueChanged)
        configureSlider(checkoutPhoneLandscapeWidthSlider, label: checkoutPhoneLandscapeWidthLabel, value: 90)
        checkoutPhoneLandscapeWidthSlider.addTarget(self, action: #selector(checkoutPhoneLandscapeWidthChanged), for: .valueChanged)
        configureSlider(checkoutPhoneLandscapeHeightSlider, label: checkoutPhoneLandscapeHeightLabel, value: 60)
        checkoutPhoneLandscapeHeightSlider.addTarget(self, action: #selector(checkoutPhoneLandscapeHeightChanged), for: .valueChanged)
        configureSlider(checkoutTabletPortraitWidthSlider, label: checkoutTabletPortraitWidthLabel, value: 40)
        checkoutTabletPortraitWidthSlider.addTarget(self, action: #selector(checkoutTabletPortraitWidthChanged), for: .valueChanged)
        configureSlider(checkoutTabletPortraitHeightSlider, label: checkoutTabletPortraitHeightLabel, value: 50)
        checkoutTabletPortraitHeightSlider.addTarget(self, action: #selector(checkoutTabletPortraitHeightChanged), for: .valueChanged)
        configureSlider(checkoutTabletLandscapeWidthSlider, label: checkoutTabletLandscapeWidthLabel, value: 30)
        checkoutTabletLandscapeWidthSlider.addTarget(self, action: #selector(checkoutTabletLandscapeWidthChanged), for: .valueChanged)
        configureSlider(checkoutTabletLandscapeHeightSlider, label: checkoutTabletLandscapeHeightLabel, value: 60)
        checkoutTabletLandscapeHeightSlider.addTarget(self, action: #selector(checkoutTabletLandscapeHeightChanged), for: .valueChanged)
    }
    
    private func setupModalSlidersAndSwitches() {
        modalShowDragBarSwitch.isOn = true
        modalAllowDismissSwitch.isOn = true
        configureSlider(modalPhonePortraitWidthSlider, label: modalPhonePortraitWidthLabel, value: 80)
        modalPhonePortraitWidthSlider.addTarget(self, action: #selector(modalPhonePortraitWidthChanged), for: .valueChanged)
        configureSlider(modalPhonePortraitHeightSlider, label: modalPhonePortraitHeightLabel, value: 50)
        modalPhonePortraitHeightSlider.addTarget(self, action: #selector(modalPhonePortraitHeightChanged), for: .valueChanged)
        configureSlider(modalPhoneLandscapeWidthSlider, label: modalPhoneLandscapeWidthLabel, value: 50)
        modalPhoneLandscapeWidthSlider.addTarget(self, action: #selector(modalPhoneLandscapeWidthChanged), for: .valueChanged)
        configureSlider(modalPhoneLandscapeHeightSlider, label: modalPhoneLandscapeHeightLabel, value: 80)
        modalPhoneLandscapeHeightSlider.addTarget(self, action: #selector(modalPhoneLandscapeHeightChanged), for: .valueChanged)
        configureSlider(modalTabletPortraitWidthSlider, label: modalTabletPortraitWidthLabel, value: 40)
        modalTabletPortraitWidthSlider.addTarget(self, action: #selector(modalTabletPortraitWidthChanged), for: .valueChanged)
        configureSlider(modalTabletPortraitHeightSlider, label: modalTabletPortraitHeightLabel, value: 30)
        modalTabletPortraitHeightSlider.addTarget(self, action: #selector(modalTabletPortraitHeightChanged), for: .valueChanged)
        configureSlider(modalTabletLandscapeWidthSlider, label: modalTabletLandscapeWidthLabel, value: 30)
        modalTabletLandscapeWidthSlider.addTarget(self, action: #selector(modalTabletLandscapeWidthChanged), for: .valueChanged)
        configureSlider(modalTabletLandscapeHeightSlider, label: modalTabletLandscapeHeightLabel, value: 40)
        modalTabletLandscapeHeightSlider.addTarget(self, action: #selector(modalTabletLandscapeHeightChanged), for: .valueChanged)
    }
    
    private func configureSlider(_ slider: UISlider, label: UILabel, value: Float) {
        slider.minimumValue = 10
        slider.maximumValue = 100
        slider.value = value
        label.text = "\(Int(value))%"
        label.font = .systemFont(ofSize: 17, weight: .regular)
        label.textColor = .secondaryLabel
    }
    
    private func setupStashPayCard() {
        StashPayCard.sharedInstance().delegate = self
        StashPayCard.sharedInstance().forcePortraitOnCheckout = forcePortraitOnCheckoutSwitch.isOn
        StashPayCard.sharedInstance().cardHeightRatioPortrait = CGFloat(phoneCardHeightSlider.value) / 100.0
        StashPayCard.sharedInstance().cardWidthRatioLandscape = CGFloat(checkoutPhoneLandscapeWidthSlider.value) / 100.0
        StashPayCard.sharedInstance().cardHeightRatioLandscape = CGFloat(checkoutPhoneLandscapeHeightSlider.value) / 100.0
        StashPayCard.sharedInstance().tabletWidthRatioPortrait = CGFloat(checkoutTabletPortraitWidthSlider.value) / 100.0
        StashPayCard.sharedInstance().tabletHeightRatioPortrait = CGFloat(checkoutTabletPortraitHeightSlider.value) / 100.0
        StashPayCard.sharedInstance().tabletWidthRatioLandscape = CGFloat(checkoutTabletLandscapeWidthSlider.value) / 100.0
        StashPayCard.sharedInstance().tabletHeightRatioLandscape = CGFloat(checkoutTabletLandscapeHeightSlider.value) / 100.0
    }
    
    // MARK: - Helpers
    
    private func systemImage(_ name: String) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular))
    }
    
    private func makeSliderCellContent(title: String, valueLabel: UILabel, slider: UISlider) -> UIView {
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
        titleLabel.font = .systemFont(ofSize: 17, weight: .regular)
        titleLabel.textColor = .label
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        topRow.addArrangedSubview(titleLabel)
        topRow.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(topRow)
        stack.addArrangedSubview(slider)
        return stack
    }
    
    // MARK: - Actions
    
    @objc private func openCheckoutTapped() {
        guard let url = checkoutUrlTextField.text, !url.isEmpty else {
            showAlert(title: "Error", message: "Please enter a checkout URL")
            return
        }
        syncCheckoutToStashPayCard()
        StashPayCard.sharedInstance().openCheckout(withURL: url)
    }
    
    private func syncCheckoutToStashPayCard() {
        let card = StashPayCard.sharedInstance()
        card.forcePortraitOnCheckout = forcePortraitOnCheckoutSwitch.isOn
        card.cardHeightRatioPortrait = CGFloat(phoneCardHeightSlider.value) / 100.0
        card.cardWidthRatioLandscape = CGFloat(checkoutPhoneLandscapeWidthSlider.value) / 100.0
        card.cardHeightRatioLandscape = CGFloat(checkoutPhoneLandscapeHeightSlider.value) / 100.0
        card.tabletWidthRatioPortrait = CGFloat(checkoutTabletPortraitWidthSlider.value) / 100.0
        card.tabletHeightRatioPortrait = CGFloat(checkoutTabletPortraitHeightSlider.value) / 100.0
        card.tabletWidthRatioLandscape = CGFloat(checkoutTabletLandscapeWidthSlider.value) / 100.0
        card.tabletHeightRatioLandscape = CGFloat(checkoutTabletLandscapeHeightSlider.value) / 100.0
    }
    
    @objc private func openModalTapped() {
        guard let url = modalUrlTextField.text, !url.isEmpty else {
            showAlert(title: "Error", message: "Please enter a modal URL")
            return
        }
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
    }
    
    @objc private func forcePortraitOnCheckoutToggled() {
        StashPayCard.sharedInstance().forcePortraitOnCheckout = forcePortraitOnCheckoutSwitch.isOn
    }
    
    @objc private func checkoutOptionsToggleTapped() {
        isCheckoutAdvancedExpanded.toggle()
        tableView.reloadSections(IndexSet(integer: Section.presentationOptions.rawValue), with: .automatic)
    }
    
    @objc private func modalOptionsToggleTapped() {
        isModalAdvancedExpanded.toggle()
        tableView.reloadSections(IndexSet(integer: Section.presentationOptions.rawValue), with: .automatic)
    }
    
    @objc private func phoneCardHeightChanged() {
        phoneCardHeightLabel.text = "\(Int(phoneCardHeightSlider.value))%"
        StashPayCard.sharedInstance().cardHeightRatioPortrait = CGFloat(phoneCardHeightSlider.value) / 100.0
    }
    @objc private func checkoutTabletPortraitWidthChanged() {
        checkoutTabletPortraitWidthLabel.text = "\(Int(checkoutTabletPortraitWidthSlider.value))%"
        StashPayCard.sharedInstance().tabletWidthRatioPortrait = CGFloat(checkoutTabletPortraitWidthSlider.value) / 100.0
    }
    @objc private func checkoutTabletPortraitHeightChanged() {
        checkoutTabletPortraitHeightLabel.text = "\(Int(checkoutTabletPortraitHeightSlider.value))%"
        StashPayCard.sharedInstance().tabletHeightRatioPortrait = CGFloat(checkoutTabletPortraitHeightSlider.value) / 100.0
    }
    @objc private func checkoutTabletLandscapeWidthChanged() {
        checkoutTabletLandscapeWidthLabel.text = "\(Int(checkoutTabletLandscapeWidthSlider.value))%"
        StashPayCard.sharedInstance().tabletWidthRatioLandscape = CGFloat(checkoutTabletLandscapeWidthSlider.value) / 100.0
    }
    @objc private func checkoutTabletLandscapeHeightChanged() {
        checkoutTabletLandscapeHeightLabel.text = "\(Int(checkoutTabletLandscapeHeightSlider.value))%"
        StashPayCard.sharedInstance().tabletHeightRatioLandscape = CGFloat(checkoutTabletLandscapeHeightSlider.value) / 100.0
    }
    @objc private func checkoutPhoneLandscapeWidthChanged() {
        checkoutPhoneLandscapeWidthLabel.text = "\(Int(checkoutPhoneLandscapeWidthSlider.value))%"
        StashPayCard.sharedInstance().cardWidthRatioLandscape = CGFloat(checkoutPhoneLandscapeWidthSlider.value) / 100.0
    }
    @objc private func checkoutPhoneLandscapeHeightChanged() {
        checkoutPhoneLandscapeHeightLabel.text = "\(Int(checkoutPhoneLandscapeHeightSlider.value))%"
        StashPayCard.sharedInstance().cardHeightRatioLandscape = CGFloat(checkoutPhoneLandscapeHeightSlider.value) / 100.0
    }
    @objc private func modalPhonePortraitWidthChanged() { modalPhonePortraitWidthLabel.text = "\(Int(modalPhonePortraitWidthSlider.value))%" }
    @objc private func modalPhonePortraitHeightChanged() { modalPhonePortraitHeightLabel.text = "\(Int(modalPhonePortraitHeightSlider.value))%" }
    @objc private func modalPhoneLandscapeWidthChanged() { modalPhoneLandscapeWidthLabel.text = "\(Int(modalPhoneLandscapeWidthSlider.value))%" }
    @objc private func modalPhoneLandscapeHeightChanged() { modalPhoneLandscapeHeightLabel.text = "\(Int(modalPhoneLandscapeHeightSlider.value))%" }
    @objc private func modalTabletPortraitWidthChanged() { modalTabletPortraitWidthLabel.text = "\(Int(modalTabletPortraitWidthSlider.value))%" }
    @objc private func modalTabletPortraitHeightChanged() { modalTabletPortraitHeightLabel.text = "\(Int(modalTabletPortraitHeightSlider.value))%" }
    @objc private func modalTabletLandscapeWidthChanged() { modalTabletLandscapeWidthLabel.text = "\(Int(modalTabletLandscapeWidthSlider.value))%" }
    @objc private func modalTabletLandscapeHeightChanged() { modalTabletLandscapeHeightLabel.text = "\(Int(modalTabletLandscapeHeightSlider.value))%" }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    @objc private func generateCheckoutTapped() {
        let baseUrl = useTestApiSwitch.isOn ? "https://test-api.stash.gg" : "https://api.stash.gg"
        let urlString = baseUrl + "/sdk/server/checkout_links/generate_quick_pay_url"
        guard let url = URL(string: urlString) else {
            showAlert(title: "Error", message: "Failed to generate checkout URL")
            return
        }
        let apiKey = apiKeyTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ViewController.defaultStashApiKey
        if !apiKey.isEmpty {
            UserDefaults.standard.set(apiKey, forKey: ViewController.userDefaultsApiKeyKey)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-stash-api-key")
        let body: [String: Any] = [
            "user": [
                "id": "test.user",
                "validatedEmail": "test@stash.gg",
                "platform": "IOS"
            ],
            "item": [
                "id": "test-item",
                "name": "Test Purchase",
                "pricePerItem": "0.99",
                "quantity": 1,
                "imageUrl": "https://api.braincloudservers.com/files/portal/g/15152/metadata/products/potion_pack.png",
                "description": "This is a test item purchase."
            ],
            "currency": "USD"
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            showAlert(title: "Error", message: "Failed to generate checkout URL")
            return
        }
        request.httpBody = bodyData
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self else { return }
            let ok = (response as? HTTPURLResponse)?.statusCode ?? 0 >= 200 && (response as? HTTPURLResponse)?.statusCode ?? 0 < 300
            guard ok, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let checkoutUrl = json["url"] as? String, !checkoutUrl.isEmpty else {
                DispatchQueue.main.async {
                    self.showAlert(title: "Error", message: "Failed to generate checkout URL")
                }
                return
            }
            DispatchQueue.main.async {
                self.syncCheckoutToStashPayCard()
                StashPayCard.sharedInstance().openCheckout(withURL: checkoutUrl)
            }
        }.resume()
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension ViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .checkout: return 3
        case .modal: return 2
        case .presentationOptions: return 1 + (isCheckoutAdvancedExpanded ? CheckoutOptionRow.allCases.count : 0) + 1 + (isModalAdvancedExpanded ? ModalOptionRow.allCases.count : 0)
        case .checkoutGenerationSettings: return 2
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let title: String?
        switch Section(rawValue: section)! {
        case .checkout: title = "CHECKOUT"
        case .modal: title = "MODAL"
        case .presentationOptions: title = "PRESENTATION OPTIONS"
        case .checkoutGenerationSettings: title = "CHECKOUT GENERATION SETTINGS"
        }
        guard let t = title else { return nil }
        let label = UILabel()
        label.text = t
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
        ])
        return container
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let text: String?
        switch Section(rawValue: section)! {
        case .checkout: text = "Drawer style dialog that slides from the bottom of the screen used for checkouts or optionally other opt-in mechanics."
        case .modal: text = "Shows centered modal window used for opt-in flows or as an alternative checkout presentation."
        default: text = nil
        }
        guard let t = text else { return nil }
        let label = UILabel()
        label.text = t
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18),
        ])
        return container
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .checkout:
            if indexPath.row == 0 {
                return urlCell(textField: checkoutUrlTextField, label: "URL", imageName: "link")
            } else if indexPath.row == 1 {
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.textLabel?.text = "Open URL in Checkout Card"
                cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
                cell.textLabel?.textColor = .systemBlue
                cell.imageView?.image = systemImage("creditcard.fill")
                cell.imageView?.tintColor = .secondaryLabel
                cell.accessoryType = .disclosureIndicator
                return cell
            } else {
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.textLabel?.text = "Generate Checkout"
                cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
                cell.textLabel?.textColor = .systemBlue
                cell.imageView?.image = systemImage("creditcard.fill")
                cell.imageView?.tintColor = .secondaryLabel
                cell.accessoryType = .disclosureIndicator
                return cell
            }
        case .modal:
            if indexPath.row == 0 {
                return urlCell(textField: modalUrlTextField, label: "URL", imageName: "link")
            } else {
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.textLabel?.text = "Open URL in Modal Dialog"
                cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
                cell.textLabel?.textColor = .systemBlue
                cell.imageView?.image = systemImage("rectangle.stack.fill")
                cell.imageView?.tintColor = .secondaryLabel
                cell.accessoryType = .disclosureIndicator
                return cell
            }
        case .presentationOptions:
            return presentationOptionCell(for: indexPath)
        case .checkoutGenerationSettings:
            if indexPath.row == 0 {
                let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
                cell.selectionStyle = .none
                cell.textLabel?.text = "Use test API"
                cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
                cell.accessoryView = useTestApiSwitch
                return cell
            } else {
                return urlCell(textField: apiKeyTextField, label: "API Key", imageName: "key")
            }
        }
    }
    
    private func urlCell(textField: UITextField, label: String, imageName: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.text = label
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        cell.textLabel?.textColor = .label
        cell.imageView?.image = systemImage(imageName)
        cell.imageView?.tintColor = .secondaryLabel
        cell.detailTextLabel?.text = nil
        if textField.superview != cell.contentView {
            textField.removeFromSuperview()
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 120),
                textField.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -36),
                textField.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                textField.heightAnchor.constraint(equalToConstant: 22),
            ])
        }
        return cell
    }
    
    private func presentationOptionCell(for indexPath: IndexPath) -> UITableViewCell {
        let r = indexPath.row
        let checkoutCount = isCheckoutAdvancedExpanded ? CheckoutOptionRow.allCases.count : 0
        let modalHeaderIndex = 1 + checkoutCount

        if r == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = isCheckoutAdvancedExpanded ? "Hide Checkout options" : "Show Checkout options"
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
            cell.textLabel?.textColor = .label
            cell.accessoryType = isCheckoutAdvancedExpanded ? .detailButton : .disclosureIndicator
            cell.imageView?.image = systemImage("slider.horizontal.3")
            cell.imageView?.tintColor = .secondaryLabel
            return cell
        }
        if isCheckoutAdvancedExpanded && r >= 1 && r < 1 + checkoutCount {
            let row = CheckoutOptionRow(rawValue: r - 1)!
            switch row {
            case .webViewMode: return switchCell(title: "Use Web View Mode", subtitle: "Open in Safari", switchView: webViewModeSwitch)
            case .forcePortraitOnCheckout: return switchCell(title: "Force Portrait on Checkout", subtitle: "Rotate to portrait when opening checkout", switchView: forcePortraitOnCheckoutSwitch)
            case .phoneCardHeight: return sliderCell(title: "Phone Card Height", valueLabel: phoneCardHeightLabel, slider: phoneCardHeightSlider)
            case .phoneLandscapeWidth: return sliderCell(title: "Phone Landscape Width", valueLabel: checkoutPhoneLandscapeWidthLabel, slider: checkoutPhoneLandscapeWidthSlider)
            case .phoneLandscapeHeight: return sliderCell(title: "Phone Landscape Height", valueLabel: checkoutPhoneLandscapeHeightLabel, slider: checkoutPhoneLandscapeHeightSlider)
            case .tabletPortraitWidth: return sliderCell(title: "Tablet Portrait Width", valueLabel: checkoutTabletPortraitWidthLabel, slider: checkoutTabletPortraitWidthSlider)
            case .tabletPortraitHeight: return sliderCell(title: "Tablet Portrait Height", valueLabel: checkoutTabletPortraitHeightLabel, slider: checkoutTabletPortraitHeightSlider)
            case .tabletLandscapeWidth: return sliderCell(title: "Tablet Landscape Width", valueLabel: checkoutTabletLandscapeWidthLabel, slider: checkoutTabletLandscapeWidthSlider)
            case .tabletLandscapeHeight: return sliderCell(title: "Tablet Landscape Height", valueLabel: checkoutTabletLandscapeHeightLabel, slider: checkoutTabletLandscapeHeightSlider)
            }
        }
        if r == modalHeaderIndex {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = isModalAdvancedExpanded ? "Hide Modal options" : "Show Modal options"
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
            cell.textLabel?.textColor = .label
            cell.accessoryType = isModalAdvancedExpanded ? .detailButton : .disclosureIndicator
            cell.imageView?.image = systemImage("rectangle.inset.filled")
            cell.imageView?.tintColor = .secondaryLabel
            return cell
        }
        if isModalAdvancedExpanded && r > modalHeaderIndex {
            let row = ModalOptionRow(rawValue: r - modalHeaderIndex - 1)!
            switch row {
            case .showDragBar: return switchCell(title: "Show Drag Bar", subtitle: nil, switchView: modalShowDragBarSwitch)
            case .allowDismiss: return switchCell(title: "Allow Dismiss", subtitle: "Tap outside to close", switchView: modalAllowDismissSwitch)
            case .modalPhonePortraitWidth: return sliderCell(title: "Phone Portrait Width", valueLabel: modalPhonePortraitWidthLabel, slider: modalPhonePortraitWidthSlider)
            case .modalPhonePortraitHeight: return sliderCell(title: "Phone Portrait Height", valueLabel: modalPhonePortraitHeightLabel, slider: modalPhonePortraitHeightSlider)
            case .modalPhoneLandscapeWidth: return sliderCell(title: "Phone Landscape Width", valueLabel: modalPhoneLandscapeWidthLabel, slider: modalPhoneLandscapeWidthSlider)
            case .modalPhoneLandscapeHeight: return sliderCell(title: "Phone Landscape Height", valueLabel: modalPhoneLandscapeHeightLabel, slider: modalPhoneLandscapeHeightSlider)
            case .modalTabletPortraitWidth: return sliderCell(title: "Tablet Portrait Width", valueLabel: modalTabletPortraitWidthLabel, slider: modalTabletPortraitWidthSlider)
            case .modalTabletPortraitHeight: return sliderCell(title: "Tablet Portrait Height", valueLabel: modalTabletPortraitHeightLabel, slider: modalTabletPortraitHeightSlider)
            case .modalTabletLandscapeWidth: return sliderCell(title: "Tablet Landscape Width", valueLabel: modalTabletLandscapeWidthLabel, slider: modalTabletLandscapeWidthSlider)
            case .modalTabletLandscapeHeight: return sliderCell(title: "Tablet Landscape Height", valueLabel: modalTabletLandscapeHeightLabel, slider: modalTabletLandscapeHeightSlider)
            }
        }
        return UITableViewCell()
    }
    
    private func switchCell(title: String, subtitle: String?, switchView: UISwitch) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.text = title
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.text = subtitle
        cell.detailTextLabel?.font = .systemFont(ofSize: 13, weight: .regular)
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryView = switchView
        return cell
    }
    
    private func sliderCell(title: String, valueLabel: UILabel, slider: UISlider) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        let content = makeSliderCellContent(title: title, valueLabel: valueLabel, slider: slider)
        cell.contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
        ])
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .checkout where indexPath.row == 1:
            openCheckoutTapped()
        case .checkout where indexPath.row == 2:
            generateCheckoutTapped()
        case .modal where indexPath.row == 1:
            openModalTapped()
        case .presentationOptions:
            let checkoutCount = isCheckoutAdvancedExpanded ? CheckoutOptionRow.allCases.count : 0
            let modalHeaderIndex = 1 + checkoutCount
            if indexPath.row == 0 {
                checkoutOptionsToggleTapped()
            } else if indexPath.row == modalHeaderIndex {
                modalOptionsToggleTapped()
            }
        default:
            break
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section)! {
        case .presentationOptions:
            let r = indexPath.row
            let checkoutCount = isCheckoutAdvancedExpanded ? CheckoutOptionRow.allCases.count : 0
            let modalHeaderIndex = 1 + checkoutCount
            if r > 0 && r < 1 + checkoutCount {
                let row = CheckoutOptionRow(rawValue: r - 1)!
                switch row {
                case .phoneCardHeight, .phoneLandscapeWidth, .phoneLandscapeHeight, .tabletPortraitWidth, .tabletPortraitHeight, .tabletLandscapeWidth, .tabletLandscapeHeight:
                    return 72
                default: return 44
                }
            }
            if r > modalHeaderIndex {
                let row = ModalOptionRow(rawValue: r - modalHeaderIndex - 1)!
                switch row {
                case .modalPhonePortraitWidth, .modalPhonePortraitHeight, .modalPhoneLandscapeWidth, .modalPhoneLandscapeHeight, .modalTabletPortraitWidth, .modalTabletPortraitHeight, .modalTabletLandscapeWidth, .modalTabletLandscapeHeight:
                    return 72
                default: return 44
                }
            }
        default: break
        }
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        44
    }
}

// MARK: - StashPayCardDelegate

extension ViewController: StashPayCardDelegate {
    
    func stashPayCardDidCompletePayment() {
        DispatchQueue.main.async {
            self.showAlert(title: "Success", message: "Purchase Successful")
        }
    }
    
    func stashPayCardDidFailPayment() {
        DispatchQueue.main.async {
            self.showAlert(title: "Payment Failed", message: "Purchase Failed")
        }
    }
    
    func stashPayCardDidDismiss() {}
    
    func stashPayCardDidReceiveOpt(in optinType: String) {
        DispatchQueue.main.async {
            self.showAlert(title: "Opt-in", message: "Opt-in Selected: \(optinType)")
        }
    }
    
    func stashPayCardDidLoadPage(_ loadTimeMs: Double) {}
    
    func stashPayCardDidEncounterNetworkError() {
        // No outcome row for network error per plan
    }
}
