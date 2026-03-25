//
//  ViewController.swift
//  StashNativeSample
//
//  Sample view controller demonstrating StashNativeCard SDK integration.
//  Designed to match Apple's Human Interface Guidelines and Settings-style layout.
//

import UIKit
import StashNative
// StashNative is imported via bridging header

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

    let modalShowDragBarSwitch = UISwitch()
    let modalAllowDismissSwitch = UISwitch()
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
    }

    /// Card option rows (when card expandable is expanded).
    enum CheckoutOptionRow: Int, CaseIterable {
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
    enum ModalOptionRow: Int, CaseIterable {
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
    static let defaultStashApiKey = "QtwPBppVziJPg7NAcfH1sbwkwx5DRbYJtezohJvFy4z505D8zNYOtstVVtJvNfxg"
    static let userDefaultsApiKeyKey = "StashApiKey"
    var stashApiKey = ViewController.defaultStashApiKey
    var useTestApi = true
    let apiKeyTextField = UITextField()
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

    func setupTextFields() {
        checkoutUrlTextField.placeholder = "URL"
        checkoutUrlTextField.text = defaultURL
        checkoutUrlTextField.autocapitalizationType = .none
        checkoutUrlTextField.autocorrectionType = .no
        checkoutUrlTextField.keyboardType = .URL
        checkoutUrlTextField.textAlignment = .right
        checkoutUrlTextField.font = .systemFont(ofSize: 17, weight: .regular)
        checkoutUrlTextField.clearButtonMode = .whileEditing

        browserUrlTextField.placeholder = "URL"
        browserUrlTextField.text = defaultURL
        browserUrlTextField.autocapitalizationType = .none
        browserUrlTextField.autocorrectionType = .no
        browserUrlTextField.keyboardType = .URL
        browserUrlTextField.textAlignment = .right
        browserUrlTextField.font = .systemFont(ofSize: 17, weight: .regular)
        browserUrlTextField.clearButtonMode = .whileEditing

        modalUrlTextField.placeholder = "URL"
        modalUrlTextField.text = defaultModalURL
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

    @objc func apiKeyEditingDidEnd() {
        let key = apiKeyTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        UserDefaults.standard.set(key.isEmpty ? nil : key, forKey: ViewController.userDefaultsApiKeyKey)
    }

    func setupStashNativeCard() {
        StashNativeCard.sharedInstance().delegate = self
    }

    // MARK: - Helpers

    func systemImage(_ name: String) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular))
    }

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
        titleLabel.font = .systemFont(ofSize: 17, weight: .regular)
        titleLabel.textColor = .label
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        topRow.addArrangedSubview(titleLabel)
        topRow.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(topRow)
        stack.addArrangedSubview(slider)
        return stack
    }

    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
