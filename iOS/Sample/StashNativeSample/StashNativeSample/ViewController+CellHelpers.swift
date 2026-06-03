//
//  ViewController+CellHelpers.swift
//  StashNativeSample
//
//  Helper methods for creating table view cells.
//

import UIKit

// MARK: - Cell Creation Helpers

extension ViewController {

    /// Shared sizing and type tokens for the settings list.
    enum Layout {
        static let bodyFont = UIFont.systemFont(ofSize: 17, weight: .regular)
        static let subtitleFont = UIFont.systemFont(ofSize: 13, weight: .regular)
        static let sectionHeaderFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
        static let contentInset: CGFloat = 20
        static let standardRowHeight: CGFloat = 44
        static let sliderRowHeight: CGFloat = 72
    }

    func footerText(for section: Section) -> String? {
        switch section {
        case .card:
            return """
                Opens an in-app card drawer that slides from the bottom of the screen. \
                Used for Stash Pay / Stash Webshop. Supports direct callbacks to application.
                """
        case .modal:
            return """
                Opens centered modal with screen rotation support. \
                Used for opt-in dialogs or as an alternative presentation for Stash Pay. \
                Supports direct callbacks to application.
                """
        case .browser:
            return """
                Opens the Stash Pay / Stash Webshop URL inside in-app browser. \
                Requires deep linking setup for callbacks.
                """
        case .checkoutGenerationSettings:
            return "Use your own API key if needed. Prefilled with demo API test key."
        case .presentationOptions:
            return nil
        case .gameSimulation:
            return """
                Simulates a landscape-locked game engine (Unity, Unreal). \
                Test: 1. Toggle on → app stays landscape. \
                2. Enable "Force Portrait on Card" above. \
                3. Open card → card and keyboard appear in portrait. \
                4. Dismiss → app returns to landscape.
                """
        }
    }

    func cardSectionCell(for indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.row {
        case 0: return urlCell(textField: checkoutUrlTextField, label: "URL")
        case 1: return actionCell(title: "Open URL in Card")
        case 2: return actionCell(title: "Generate Checkout")
        default: return actionCell(title: "Open Webshop")
        }
    }

    func modalSectionCell(for indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            return urlCell(textField: modalUrlTextField, label: "URL")
        }
        return actionCell(title: "Open URL in Modal Dialog")
    }

    func browserSectionCell(for indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.row {
        case 0: return urlCell(textField: browserUrlTextField, label: "URL")
        case 1: return actionCell(title: "Open URL in Browser")
        default: return actionCell(title: "Generate Checkout")
        }
    }

    func checkoutGenerationCell(for indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            return switchCell(title: "Use test API", subtitle: nil, switchView: useTestApiSwitch)
        }
        return urlCell(textField: apiKeyTextField, label: "API Key")
    }

    func gameSimulationCell(for indexPath: IndexPath) -> UITableViewCell {
        return switchCell(
            title: "Lock app to Landscape",
            subtitle: "Simulates a landscape-locked game engine",
            switchView: simulateLandscapeSwitch
        )
    }

    /// A tappable row with an accent title and a disclosure chevron.
    func actionCell(title: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.textLabel?.font = Layout.bodyFont
        cell.textLabel?.textColor = .systemBlue
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    /// A label on the left and a right-aligned editable value field.
    func urlCell(textField: UITextField, label: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.text = label
        cell.textLabel?.font = Layout.bodyFont
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.text = nil
        if textField.superview != cell.contentView {
            textField.removeFromSuperview()
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(textField)
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 96),
                textField.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                textField.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                textField.heightAnchor.constraint(equalToConstant: 22)
            ])
        }
        return cell
    }

    func switchCell(title: String, subtitle: String?, switchView: UISwitch) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.text = title
        cell.textLabel?.font = Layout.bodyFont
        cell.textLabel?.textColor = .label
        cell.detailTextLabel?.text = subtitle
        cell.detailTextLabel?.font = Layout.subtitleFont
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.accessoryView = switchView
        return cell
    }

    func sliderCell(title: String, valueLabel: UILabel, slider: UISlider) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        let content = makeSliderCellContent(title: title, valueLabel: valueLabel, slider: slider)
        cell.contentView.addSubview(content)
        let margins = cell.contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)
        ])
        return cell
    }
}
