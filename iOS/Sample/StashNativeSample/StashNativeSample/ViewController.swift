//
//  ViewController.swift
//  StashNativeSample
//
//  StashNativeCard SDK sample with Settings-style layout.
//

import UIKit
import StashNative
import Security

/// A named Stash app credential: the app ID plus its ingress secret, with a production/test flag.
/// Both are needed to sign requests (see `StashHmac`).
class ViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Properties

    lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.delegate = self
        table.dataSource = self
        table.keyboardDismissMode = .onDrag
        return table
    }()

    /// Stash wordmark shown in place of the Test-tab title. Template-rendered so it tints with
    /// the label color and adapts to light/dark.
    lazy var logoView: UIImageView = {
        let image = UIImage(named: "StashLogo")?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .label
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let height: CGFloat = 24
        let ratio = (image?.size.width ?? 1000) / (image?.size.height ?? 253)
        NSLayoutConstraint.activate([
            imageView.heightAnchor.constraint(equalToConstant: height),
            imageView.widthAnchor.constraint(equalToConstant: height * ratio)
        ])
        return imageView
    }()

    /// Import/export action, shown only on the Instances tab.
    lazy var instancesTransferBarItem: UIBarButtonItem = {
        let item = UIBarButtonItem(image: UIImage(named: "ImportExport"),
                                   style: .plain, target: self,
                                   action: #selector(importExportTapped))
        item.accessibilityLabel = "Import / Export"
        return item
    }()

    @objc func importExportTapped() {
        present(UINavigationController(
            rootViewController: InstancesTransferViewController(host: self)), animated: true)
    }

    /// Add-instance action, shown only on the Instances tab beside import/export.
    lazy var addInstanceBarItem: UIBarButtonItem = {
        let item = UIBarButtonItem(barButtonSystemItem: .add, target: self,
                                   action: #selector(addInstanceTapped))
        item.accessibilityLabel = "Add Instance"
        return item
    }()

    @objc func addInstanceTapped() {
        showAddApiKey()
    }

    /// Leading bar item so the wordmark sits left-aligned, matching the Android toolbar.
    /// iOS 26 draws a glass capsule behind bar items; suppress it so the logo reads as a
    /// wordmark rather than a button.
    lazy var logoBarItem: UIBarButtonItem = {
        let item = UIBarButtonItem(customView: logoView)
        if #available(iOS 26.0, *) {
            item.hidesSharedBackground = true
        }
        return item
    }()

    let defaultURL = "https://test.stashpreview.com/"

    let checkoutUrlTextField = UITextField()
    let browserUrlTextField = UITextField()
    /// Top stack that shows every SDK callback as a chip, newest on top.
    let callbackChipStack = UIStackView()
    /// Bottom tab bar splitting the page into Test / Settings / API views.
    let tabBar = UITabBar()
    /// Explicit height for the standalone tab bar on pre-iOS-26 (see updateTabBarHeight).
    var tabBarHeightConstraint: NSLayoutConstraint?
    let cardPreferPortraitSwitch = UISwitch()
    let cardAllowDismissSwitch = UISwitch()
    let cardAutoCloseSwitch = UISwitch()
    let cardPreferredWidthSlider = UISlider()
    let cardPreferredWidthLabel = UILabel()
    let cardPreferredHeightSlider = UISlider()
    let cardPreferredHeightLabel = UILabel()
    let cardMaximumHeightSlider = UISlider()
    let cardMaximumHeightLabel = UILabel()
    let cardEdgeMarginSlider = UISlider()
    let cardEdgeMarginLabel = UILabel()

    // API keys: named, each production or test; Keychain-persisted (survives reinstall).
    var apiKeys: [ApiKeyEntry] = []
    var selectedApiKeyId: String?
    var pendingAlerts: [(String, String)] = []

    // MARK: - App orientation lock
    var lockLandscape = false
    let lockLandscapeSwitch = UISwitch()

    #if DEBUG
    var handledLaunchPresentation = false
    #endif

    enum Section {
        case card
        case browser
        case presentationOptions
        case other
        case about
        case checkoutGenerationSettings
    }

    /// Bottom-nav tabs; each shows a subset of sections.
    enum Tab: Int {
        case test
        case settings
        case api
    }

    var currentTab: Tab = .test

    /// Sections visible for the current tab, in display order.
    var visibleSections: [Section] {
        switch currentTab {
        case .test: return [.card, .browser]
        case .settings: return [.presentationOptions, .other, .about]
        case .api: return [.checkoutGenerationSettings]
        }
    }

    func visibleSection(at index: Int) -> Section? {
        guard index >= 0 && index < visibleSections.count else { return nil }
        return visibleSections[index]
    }

    /// Card option rows, rendered by OptionsListViewController.
    enum CheckoutOptionRow {
        case preferPortrait
        case allowDismiss
        case cardAutoClose
        case preferredWidth
        case preferredHeight
        case maximumHeight
        case edgeMargin
    }
    /// Value label for each slider, so one handler serves them all.
    var sliderLabels: [UISlider: UILabel] = [:]

    // MARK: - Instance credentials
    /// Demo ingress secret (base64) used as the HMAC key when no key is configured.
    static let defaultStashApiKey =
        "VDBsMm5zRU9weHk5RTZ6X0p2Y3hnLVhrMHVvS21QMG5wYTBJcmhHUHdWTV93Y0dDWVluV0hQd1ZYWHRiYWk2UA=="
    /// Demo app ID that pairs with the secret above; required by the signature header.
    static let defaultStashAppId = "4fe1c1a4-b136-4187-82f2-61c9983eedf2"
    /// Display name of the bundled credential.
    static let defaultStashKeyName = "Howling Woods"
    /// Secrets previously shipped as the bundled credential.
    static let supersededBundledSecrets = [
        "QtwPBppVziJPg7NAcfH1sbwkwx5DRbYJtezohJvFy4z505D8zNYOtstVVtJvNfxg"
    ]

    /// True if the key is a superseded bundled secret that should migrate to the current one.
    static func isSupersededBundledSecret(_ key: String) -> Bool {
        supersededBundledSecrets.contains(key)
    }

    /// The bundled demo credential, seeded with the default request bodies.
    static func bundledEntry() -> ApiKeyEntry {
        ApiKeyEntry(id: UUID().uuidString, name: defaultStashKeyName,
                    appId: defaultStashAppId, key: defaultStashApiKey, production: false,
                    checkoutPayload: defaultCheckoutPayload, webshopPayload: defaultWebshopPayload)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        applyHeader(for: currentTab)

        loadApiKeys()
        setupTextFields()
        setupCheckoutSlidersAndSwitches()
        setupLockLandscape()
        setupTabBar()
        setupStashNativeCard()

        view.addSubview(tableView)
        view.addSubview(tabBar)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: tabBar.topAnchor),

            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        // A bare UITabBar (not owned by a UITabBarController) does not inflate its intrinsic
        // height by the bottom safe-area inset on iOS 18 and earlier, so its items render down
        // inside the home-indicator region. Pin an explicit height on those versions; iOS 26's
        // floating tab bar self-manages its layout, so leave it to intrinsic sizing there.
        if #unavailable(iOS 26.0) {
            let heightConstraint = tabBar.heightAnchor.constraint(
                equalToConstant: tabBar.intrinsicContentSize.height)
            heightConstraint.isActive = true
            tabBarHeightConstraint = heightConstraint
        }

        callbackChipStack.axis = .vertical
        callbackChipStack.alignment = .fill
        callbackChipStack.spacing = 8
        callbackChipStack.translatesAutoresizingMaskIntoConstraints = false
        callbackChipStack.isUserInteractionEnabled = true
        // Host on the navigation controller's view so chips overlay the nav bar too; this VC's
        // own view sits underneath it. Falls back to our view if there is no nav controller.
        let chipHost: UIView = navigationController?.view ?? view
        chipHost.addSubview(callbackChipStack)
        NSLayoutConstraint.activate([
            callbackChipStack.leadingAnchor.constraint(equalTo: chipHost.leadingAnchor, constant: 12),
            callbackChipStack.trailingAnchor.constraint(equalTo: chipHost.trailingAnchor, constant: -12),
            callbackChipStack.topAnchor.constraint(
                equalTo: chipHost.safeAreaLayoutGuide.topAnchor, constant: 8)
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        flushPendingAlertsIfPossible()
        #if DEBUG
        openLaunchPresentationIfNeeded()
        #endif
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        // Reserve the bottom safe-area inset above the bar's own content height so items clear
        // the home indicator. Intrinsic height tracks portrait (49) vs landscape (32) so the
        // bar stays native in both. No-op on iOS 26, where tabBarHeightConstraint is nil.
        tabBarHeightConstraint?.constant =
            tabBar.intrinsicContentSize.height + view.safeAreaInsets.bottom
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        lockLandscape ? .landscape : .all
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
        field.font = .systemFont(ofSize: 17, weight: .regular)
        field.clearButtonMode = .whileEditing
    }

    func setupTextFields() {
        configureStandardUrlTextField(checkoutUrlTextField, text: defaultURL)
        configureStandardUrlTextField(browserUrlTextField, text: defaultURL)
        // Stable ids for UI tests. The Open button ids are derived from these in urlCell.
        checkoutUrlTextField.accessibilityIdentifier = "card-url-field"
        browserUrlTextField.accessibilityIdentifier = "browser-url-field"

    }

    func setupStashNativeCard() {
        StashNativeCard.sharedInstance().delegate = self
    }

    func setupTabBar() {
        let test = UITabBarItem(
            title: "Test", image: UIImage(systemName: "creditcard"), tag: Tab.test.rawValue)
        let settings = UITabBarItem(
            title: "Settings", image: UIImage(systemName: "slider.horizontal.3"),
            tag: Tab.settings.rawValue)
        let api = UITabBarItem(
            title: "Instances", image: UIImage(systemName: "key"), tag: Tab.api.rawValue)
        tabBar.items = [test, settings, api]
        tabBar.selectedItem = test
        tabBar.delegate = self
    }

}
