//
//  ViewController+CellHelpers+PresentationOptions.swift
//  StashNativeSample
//
//  Presentation options section (orientation lock + navigation to option screens)
//  and the card option rows reused by the pushed OptionsListViewController.
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
        navCell("Card options")
    }

    func handlePresentationOptionsSelection(at indexPath: IndexPath) {
        switch indexPath.row {
        case 0: openCardOptionsTapped()
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

    // MARK: - Responsive presentation options

    func cardOptionCell(for row: CheckoutOptionRow) -> UITableViewCell {
        switch row {
        case .preferPortrait:
            return switchCell(title: "Prefer portrait",
                              subtitle: "Portrait checkout on iPhone, including landscape games; ignored on iPad",
                              switchView: cardPreferPortraitSwitch)
        case .allowDismiss:
            return switchCell(title: "Allow dismissal", subtitle: "Swipe or tap outside to close",
                              switchView: cardAllowDismissSwitch)
        case .cardAutoClose:
            return switchCell(title: "Auto-close on payment event", subtitle: "Close card after success/failure",
                              switchView: cardAutoCloseSwitch)
        case .preferredWidth:
            return sliderCell(title: "Preferred content width", valueLabel: cardPreferredWidthLabel,
                              slider: cardPreferredWidthSlider)
        case .preferredHeight:
            return sliderCell(title: "Preferred content height", valueLabel: cardPreferredHeightLabel,
                              slider: cardPreferredHeightSlider)
        case .maximumHeight:
            return sliderCell(title: "Maximum content height", valueLabel: cardMaximumHeightLabel,
                              slider: cardMaximumHeightSlider)
        case .edgeMargin:
            return sliderCell(title: "Edge margin", valueLabel: cardEdgeMarginLabel, slider: cardEdgeMarginSlider)
        }
    }

    func cardOptionHeight(for row: CheckoutOptionRow) -> CGFloat {
        switch row {
        case .preferPortrait, .allowDismiss, .cardAutoClose:
            return UITableView.automaticDimension
        default:
            return 72
        }
    }

}

// MARK: - Card options screen

/// Reuses the host controls so edits flow into buildCardConfig().
final class OptionsListViewController: UITableViewController {

    private weak var host: ViewController?

    private let sectionTitles = ["General", "Responsive size"]

    private let cardSections: [[ViewController.CheckoutOptionRow]] = [
        [.preferPortrait, .allowDismiss, .cardAutoClose],
        [.preferredWidth, .preferredHeight, .maximumHeight, .edgeMargin]
    ]

    init(host: ViewController) {
        self.host = host
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Card options"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        tableView.estimatedRowHeight = 56
    }

    override func numberOfSections(in tableView: UITableView) -> Int { sectionTitles.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sectionTitles[section]
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 1 else { return nil }
        let sizing = "The card follows content up to the preferred height and can expand for scrolling."
        return "\(sizing) Dimensions use points of web content. A maximum of zero uses available height."
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        cardSections[section].count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let host = host else { return UITableViewCell() }
        return host.cardOptionCell(for: cardSections[indexPath.section][indexPath.row])
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let host = host else { return 56 }
        return host.cardOptionHeight(for: cardSections[indexPath.section][indexPath.row])
    }
}
