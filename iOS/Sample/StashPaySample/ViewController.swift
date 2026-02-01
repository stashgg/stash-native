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
    private let statusLabel = UILabel()
    
    // Advanced options - Checkout (one row per option when expanded)
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
    
    private enum Section: Int, CaseIterable {
        case checkout
        case modal
        case status
        case checkoutOptions
        case modalOptions
    }
    
    private enum CheckoutOptionRow: Int, CaseIterable {
        case header
        case webViewMode
        case landscapeLock
        case phoneCardHeight
        case tabletPortraitWidth
        case tabletPortraitHeight
        case tabletLandscapeWidth
        case tabletLandscapeHeight
    }
    
    private enum ModalOptionRow: Int, CaseIterable {
        case header
        case showDragBar
        case allowDismiss
        case phonePortraitWidth
        case phonePortraitHeight
        case phoneLandscapeWidth
        case phoneLandscapeHeight
        case tabletPortraitWidth
        case tabletPortraitHeight
        case tabletLandscapeWidth
        case tabletLandscapeHeight
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Stash SDK"
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
        return isLandscapeLocked ? .landscape : .all
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
        modalUrlTextField.text = "https://store.howlingwoods.shop/pay/channel-selection"
        modalUrlTextField.autocapitalizationType = .none
        modalUrlTextField.autocorrectionType = .no
        modalUrlTextField.keyboardType = .URL
        modalUrlTextField.textAlignment = .right
        modalUrlTextField.font = .systemFont(ofSize: 17, weight: .regular)
        modalUrlTextField.clearButtonMode = .whileEditing
        
        statusLabel.text = "Ready"
        statusLabel.font = .systemFont(ofSize: 17, weight: .regular)
        statusLabel.textColor = .secondaryLabel
    }
    
    private func setupCheckoutSlidersAndSwitches() {
        webViewModeSwitch.addTarget(self, action: #selector(webViewModeToggled), for: .valueChanged)
        landscapeLockSwitch.addTarget(self, action: #selector(landscapeLockToggled), for: .valueChanged)
        configureSlider(phoneCardHeightSlider, label: phoneCardHeightLabel, value: 68)
        phoneCardHeightSlider.addTarget(self, action: #selector(phoneCardHeightChanged), for: .valueChanged)
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
        configureSlider(modalTabletPortraitWidthSlider, label: modalTabletPortraitWidthLabel, value: 60)
        modalTabletPortraitWidthSlider.addTarget(self, action: #selector(modalTabletPortraitWidthChanged), for: .valueChanged)
        configureSlider(modalTabletPortraitHeightSlider, label: modalTabletPortraitHeightLabel, value: 70)
        modalTabletPortraitHeightSlider.addTarget(self, action: #selector(modalTabletPortraitHeightChanged), for: .valueChanged)
        configureSlider(modalTabletLandscapeWidthSlider, label: modalTabletLandscapeWidthLabel, value: 50)
        modalTabletLandscapeWidthSlider.addTarget(self, action: #selector(modalTabletLandscapeWidthChanged), for: .valueChanged)
        configureSlider(modalTabletLandscapeHeightSlider, label: modalTabletLandscapeHeightLabel, value: 80)
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
        StashPayCard.sharedInstance().cardHeightRatioPortrait = CGFloat(phoneCardHeightSlider.value) / 100.0
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
        statusLabel.text = webViewModeSwitch.isOn ? "Web View (Safari)" : "Card UI"
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
        isCheckoutAdvancedExpanded.toggle()
        tableView.reloadSections(IndexSet(integer: Section.checkoutOptions.rawValue), with: .automatic)
    }
    
    @objc private func advancedModalToggleTapped() {
        isModalAdvancedExpanded.toggle()
        tableView.reloadSections(IndexSet(integer: Section.modalOptions.rawValue), with: .automatic)
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
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension ViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .checkout: return 2
        case .modal: return 2
        case .status: return 1
        case .checkoutOptions: return isCheckoutAdvancedExpanded ? CheckoutOptionRow.allCases.count : 1
        case .modalOptions: return isModalAdvancedExpanded ? ModalOptionRow.allCases.count : 1
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let title: String?
        switch Section(rawValue: section)! {
        case .checkout: title = "CHECKOUT"
        case .modal: title = "MODAL"
        case .status: title = "STATUS"
        case .checkoutOptions: title = "CHECKOUT OPTIONS"
        case .modalOptions: title = "MODAL OPTIONS"
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
        case .checkout: text = "Open a full-screen checkout experience."
        case .modal: text = "Open a modal sheet for channel or payment selection."
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
            } else {
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.textLabel?.text = "Open Checkout"
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
                cell.textLabel?.text = "Open Modal"
                cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
                cell.textLabel?.textColor = .systemBlue
                cell.imageView?.image = systemImage("rectangle.stack.fill")
                cell.imageView?.tintColor = .secondaryLabel
                cell.accessoryType = .disclosureIndicator
                return cell
            }
        case .status:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.selectionStyle = .none
            cell.textLabel?.text = "Status"
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
            cell.detailTextLabel?.text = statusLabel.text
            cell.detailTextLabel?.font = .systemFont(ofSize: 17, weight: .regular)
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.imageView?.image = systemImage("antenna.radiowaves.left.and.right")
            cell.imageView?.tintColor = .secondaryLabel
            return cell
        case .checkoutOptions:
            return checkoutOptionCell(for: indexPath)
        case .modalOptions:
            return modalOptionCell(for: indexPath)
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
    
    private func checkoutOptionCell(for indexPath: IndexPath) -> UITableViewCell {
        let row = CheckoutOptionRow(rawValue: indexPath.row)!
        switch row {
        case .header:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Checkout Options"
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
            cell.textLabel?.textColor = .label
            cell.accessoryType = isCheckoutAdvancedExpanded ? .detailButton : .disclosureIndicator
            cell.imageView?.image = systemImage("slider.horizontal.3")
            cell.imageView?.tintColor = .secondaryLabel
            return cell
        case .webViewMode:
            return switchCell(title: "Use Web View Mode", subtitle: "Open in Safari", switchView: webViewModeSwitch)
        case .landscapeLock:
            return switchCell(title: "Lock to Landscape", subtitle: nil, switchView: landscapeLockSwitch)
        case .phoneCardHeight:
            return sliderCell(title: "Phone Card Height", valueLabel: phoneCardHeightLabel, slider: phoneCardHeightSlider)
        case .tabletPortraitWidth:
            return sliderCell(title: "Tablet Portrait Width", valueLabel: checkoutTabletPortraitWidthLabel, slider: checkoutTabletPortraitWidthSlider)
        case .tabletPortraitHeight:
            return sliderCell(title: "Tablet Portrait Height", valueLabel: checkoutTabletPortraitHeightLabel, slider: checkoutTabletPortraitHeightSlider)
        case .tabletLandscapeWidth:
            return sliderCell(title: "Tablet Landscape Width", valueLabel: checkoutTabletLandscapeWidthLabel, slider: checkoutTabletLandscapeWidthSlider)
        case .tabletLandscapeHeight:
            return sliderCell(title: "Tablet Landscape Height", valueLabel: checkoutTabletLandscapeHeightLabel, slider: checkoutTabletLandscapeHeightSlider)
        }
    }
    
    private func modalOptionCell(for indexPath: IndexPath) -> UITableViewCell {
        let row = ModalOptionRow(rawValue: indexPath.row)!
        switch row {
        case .header:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Modal Options"
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
            cell.textLabel?.textColor = .label
            cell.accessoryType = isModalAdvancedExpanded ? .none : .disclosureIndicator
            cell.imageView?.image = systemImage("rectangle.inset.filled")
            cell.imageView?.tintColor = .secondaryLabel
            return cell
        case .showDragBar:
            return switchCell(title: "Show Drag Bar", subtitle: nil, switchView: modalShowDragBarSwitch)
        case .allowDismiss:
            return switchCell(title: "Allow Dismiss", subtitle: "Tap outside to close", switchView: modalAllowDismissSwitch)
        case .phonePortraitWidth:
            return sliderCell(title: "Phone Portrait Width", valueLabel: modalPhonePortraitWidthLabel, slider: modalPhonePortraitWidthSlider)
        case .phonePortraitHeight:
            return sliderCell(title: "Phone Portrait Height", valueLabel: modalPhonePortraitHeightLabel, slider: modalPhonePortraitHeightSlider)
        case .phoneLandscapeWidth:
            return sliderCell(title: "Phone Landscape Width", valueLabel: modalPhoneLandscapeWidthLabel, slider: modalPhoneLandscapeWidthSlider)
        case .phoneLandscapeHeight:
            return sliderCell(title: "Phone Landscape Height", valueLabel: modalPhoneLandscapeHeightLabel, slider: modalPhoneLandscapeHeightSlider)
        case .tabletPortraitWidth:
            return sliderCell(title: "Tablet Portrait Width", valueLabel: modalTabletPortraitWidthLabel, slider: modalTabletPortraitWidthSlider)
        case .tabletPortraitHeight:
            return sliderCell(title: "Tablet Portrait Height", valueLabel: modalTabletPortraitHeightLabel, slider: modalTabletPortraitHeightSlider)
        case .tabletLandscapeWidth:
            return sliderCell(title: "Tablet Landscape Width", valueLabel: modalTabletLandscapeWidthLabel, slider: modalTabletLandscapeWidthSlider)
        case .tabletLandscapeHeight:
            return sliderCell(title: "Tablet Landscape Height", valueLabel: modalTabletLandscapeHeightLabel, slider: modalTabletLandscapeHeightSlider)
        }
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
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if case .status = Section(rawValue: indexPath.section) {
            cell.detailTextLabel?.text = statusLabel.text
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .checkout where indexPath.row == 1:
            openCheckoutTapped()
        case .modal where indexPath.row == 1:
            openModalTapped()
        case .checkoutOptions where indexPath.row == 0:
            advancedCheckoutToggleTapped()
        case .modalOptions where indexPath.row == 0:
            advancedModalToggleTapped()
        default:
            break
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch Section(rawValue: indexPath.section)! {
        case .checkoutOptions:
            if isCheckoutAdvancedExpanded, indexPath.row > 0 {
                let row = CheckoutOptionRow(rawValue: indexPath.row)!
                switch row {
                case .phoneCardHeight, .tabletPortraitWidth, .tabletPortraitHeight, .tabletLandscapeWidth, .tabletLandscapeHeight:
                    return 72
                default: return 44
                }
            }
        case .modalOptions:
            if isModalAdvancedExpanded, indexPath.row > 0 {
                let row = ModalOptionRow(rawValue: indexPath.row)!
                switch row {
                case .phonePortraitWidth, .phonePortraitHeight, .phoneLandscapeWidth, .phoneLandscapeHeight,
                     .tabletPortraitWidth, .tabletPortraitHeight, .tabletLandscapeWidth, .tabletLandscapeHeight:
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
            self.statusLabel.text = "Payment Success"
            self.tableView.reloadData()
            self.showAlert(title: "Success", message: "Payment completed successfully")
        }
    }
    
    func stashPayCardDidFailPayment() {
        DispatchQueue.main.async {
            self.statusLabel.text = "Payment Failed"
            self.tableView.reloadData()
            self.showAlert(title: "Failed", message: "Payment failed")
        }
    }
    
    func stashPayCardDidDismiss() {
        DispatchQueue.main.async {
            self.statusLabel.text = "Dialog dismissed"
            self.tableView.reloadData()
        }
    }
    
    func stashPayCardDidReceiveOpt(in optinType: String) {
        DispatchQueue.main.async {
            self.statusLabel.text = "Opt-in: \(optinType)"
            self.tableView.reloadData()
        }
    }
    
    func stashPayCardDidLoadPage(_ loadTimeMs: Double) {}
    
    func stashPayCardDidEncounterNetworkError() {
        DispatchQueue.main.async {
            self.statusLabel.text = "Network Error"
            self.tableView.reloadData()
            self.showAlert(title: "Network Error", message: "Could not load page. Please check your connection.")
        }
    }
}
