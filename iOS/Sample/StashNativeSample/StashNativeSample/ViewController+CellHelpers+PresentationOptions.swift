//
//  ViewController+CellHelpers+PresentationOptions.swift
//  StashNativeSample
//
//  Presentation options section (orientation lock + navigation to option screens)
//  and the card/modal option rows reused by the pushed OptionsListViewController.
//

import UIKit
import StashNative

extension ViewController {

    // MARK: - About section (SDK version read from the library)

    func aboutCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.text = "SDK version"
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.text = StashNativeCard.sdkVersion()
        cell.detailTextLabel?.textColor = .secondaryLabel
        return cell
    }

    // MARK: - Presentation options section (main screen)

    func presentationOptionCell(for indexPath: IndexPath) -> UITableViewCell {
        navCell(indexPath.row == 0 ? "Card options" : "Modal options")
    }

    func handlePresentationOptionsSelection(at indexPath: IndexPath) {
        switch indexPath.row {
        case 0: openCardOptionsTapped()
        case 1: openModalOptionsTapped()
        default: break
        }
    }

    // MARK: - Other section

    /// App-level orientation lock. Android pairs this with the keep-alive switch; iOS has no
    /// keep-alive, so this section holds the one row.
    func otherCell() -> UITableViewCell {
        switchCell(title: "Lock app to landscape", subtitle: nil, switchView: lockLandscapeSwitch)
    }

    private func navCell(_ title: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        cell.textLabel?.textColor = .label
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    // MARK: - Card option rows (shown on the pushed Card options screen)

    // swiftlint:disable:next function_body_length
    func cardOptionCell(for row: CheckoutOptionRow) -> UITableViewCell {
        switch row {
        case .cardBackgroundHex:
            return urlCell(
                textField: cardBackgroundColorTextField,
                label: "Background",
                imageName: "paintpalette.fill"
            )
        case .forcePortraitOnCheckout:
            return switchCell(
                title: "Force Portrait on Card",
                subtitle: "Rotate to portrait when opening card",
                switchView: forcePortraitOnCheckoutSwitch
            )
        case .cardAutoClose:
            return switchCell(
                title: "Auto-close on payment event",
                subtitle: "Close card after success/failure",
                switchView: cardAutoCloseSwitch
            )
        case .phoneCardHeight:
            return sliderCell(
                title: "Phone Card Height",
                valueLabel: phoneCardHeightLabel,
                slider: phoneCardHeightSlider
            )
        case .phoneLandscapeWidth:
            return sliderCell(
                title: "Phone Landscape Width",
                valueLabel: checkoutPhoneLandscapeWidthLabel,
                slider: checkoutPhoneLandscapeWidthSlider
            )
        case .phoneLandscapeHeight:
            return sliderCell(
                title: "Phone Landscape Height",
                valueLabel: checkoutPhoneLandscapeHeightLabel,
                slider: checkoutPhoneLandscapeHeightSlider
            )
        case .tabletPortraitWidth:
            return sliderCell(
                title: "Tablet Portrait Width",
                valueLabel: checkoutTabletPortraitWidthLabel,
                slider: checkoutTabletPortraitWidthSlider
            )
        case .tabletPortraitHeight:
            return sliderCell(
                title: "Tablet Portrait Height",
                valueLabel: checkoutTabletPortraitHeightLabel,
                slider: checkoutTabletPortraitHeightSlider
            )
        case .tabletLandscapeWidth:
            return sliderCell(
                title: "Tablet Landscape Width",
                valueLabel: checkoutTabletLandscapeWidthLabel,
                slider: checkoutTabletLandscapeWidthSlider
            )
        case .tabletLandscapeHeight:
            return sliderCell(
                title: "Tablet Landscape Height",
                valueLabel: checkoutTabletLandscapeHeightLabel,
                slider: checkoutTabletLandscapeHeightSlider
            )
        }
    }

    func cardOptionHeight(for row: CheckoutOptionRow) -> CGFloat {
        switch row {
        case .cardBackgroundHex, .forcePortraitOnCheckout, .cardAutoClose:
            return UITableView.automaticDimension
        default:
            return 72
        }
    }

    // MARK: - Modal option rows (shown on the pushed Modal options screen)

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func modalOptionCell(for row: ModalOptionRow) -> UITableViewCell {
        switch row {
        case .modalBackgroundHex:
            return urlCell(
                textField: modalBackgroundColorTextField,
                label: "Background",
                imageName: "paintpalette.fill"
            )
        case .allowDismiss:
            return switchCell(
                title: "Allow Dismiss",
                subtitle: "Tap outside to close",
                switchView: modalAllowDismissSwitch
            )
        case .modalAutoClose:
            return switchCell(
                title: "Auto-close on payment event",
                subtitle: "Close modal after success/failure",
                switchView: modalAutoCloseSwitch
            )
        case .modalPhonePortraitWidth:
            return sliderCell(
                title: "Phone Portrait Width",
                valueLabel: modalPhonePortraitWidthLabel,
                slider: modalPhonePortraitWidthSlider
            )
        case .modalPhonePortraitHeight:
            return sliderCell(
                title: "Phone Portrait Height",
                valueLabel: modalPhonePortraitHeightLabel,
                slider: modalPhonePortraitHeightSlider
            )
        case .modalPhoneLandscapeWidth:
            return sliderCell(
                title: "Phone Landscape Width",
                valueLabel: modalPhoneLandscapeWidthLabel,
                slider: modalPhoneLandscapeWidthSlider
            )
        case .modalPhoneLandscapeHeight:
            return sliderCell(
                title: "Phone Landscape Height",
                valueLabel: modalPhoneLandscapeHeightLabel,
                slider: modalPhoneLandscapeHeightSlider
            )
        case .modalTabletPortraitWidth:
            return sliderCell(
                title: "Tablet Portrait Width",
                valueLabel: modalTabletPortraitWidthLabel,
                slider: modalTabletPortraitWidthSlider
            )
        case .modalTabletPortraitHeight:
            return sliderCell(
                title: "Tablet Portrait Height",
                valueLabel: modalTabletPortraitHeightLabel,
                slider: modalTabletPortraitHeightSlider
            )
        case .modalTabletLandscapeWidth:
            return sliderCell(
                title: "Tablet Landscape Width",
                valueLabel: modalTabletLandscapeWidthLabel,
                slider: modalTabletLandscapeWidthSlider
            )
        case .modalTabletLandscapeHeight:
            return sliderCell(
                title: "Tablet Landscape Height",
                valueLabel: modalTabletLandscapeHeightLabel,
                slider: modalTabletLandscapeHeightSlider
            )
        }
    }

    func modalOptionHeight(for row: ModalOptionRow) -> CGFloat {
        switch row {
        case .modalBackgroundHex, .allowDismiss, .modalAutoClose:
            return UITableView.automaticDimension
        default:
            return 72
        }
    }
}

// MARK: - Dedicated Card/Modal options screen

/// A pushed screen that hosts only the card (or modal) option rows. Reuses the host's shared
/// controls, so edits flow straight into buildCardConfig()/buildModalConfig().
final class OptionsListViewController: UITableViewController {

    enum Mode { case card, modal }

    private let mode: Mode
    private weak var host: ViewController?

    private let sectionTitles = ["General", "Phone Dimensions", "Tablet Dimensions"]

    /// Card option rows grouped into General / Phone / Tablet.
    private let cardSections: [[ViewController.CheckoutOptionRow]] = [
        [.cardBackgroundHex, .forcePortraitOnCheckout, .cardAutoClose],
        [.phoneCardHeight, .phoneLandscapeWidth, .phoneLandscapeHeight],
        [.tabletPortraitWidth, .tabletPortraitHeight, .tabletLandscapeWidth, .tabletLandscapeHeight]
    ]

    /// Modal option rows grouped into General / Phone / Tablet.
    private let modalSections: [[ViewController.ModalOptionRow]] = [
        [.modalBackgroundHex, .allowDismiss, .modalAutoClose],
        [.modalPhonePortraitWidth, .modalPhonePortraitHeight,
         .modalPhoneLandscapeWidth, .modalPhoneLandscapeHeight],
        [.modalTabletPortraitWidth, .modalTabletPortraitHeight,
         .modalTabletLandscapeWidth, .modalTabletLandscapeHeight]
    ]

    init(mode: Mode, host: ViewController) {
        self.mode = mode
        self.host = host
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = mode == .card ? "Card options" : "Modal options"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        tableView.estimatedRowHeight = 56
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sectionTitles.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sectionTitles[section]
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        mode == .card ? cardSections[section].count : modalSections[section].count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let host = host else { return UITableViewCell() }
        if mode == .card {
            return host.cardOptionCell(for: cardSections[indexPath.section][indexPath.row])
        }
        return host.modalOptionCell(for: modalSections[indexPath.section][indexPath.row])
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let host = host else { return 56 }
        if mode == .card {
            return host.cardOptionHeight(for: cardSections[indexPath.section][indexPath.row])
        }
        return host.modalOptionHeight(for: modalSections[indexPath.section][indexPath.row])
    }
}
