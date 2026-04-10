//
//  ViewController+CellHelpers.swift
//  StashNativeSample
//
//  Helper methods for creating table view cells.
//

import UIKit

// MARK: - Cell Creation Helpers

extension ViewController {

    static let footerFont = UIFont.systemFont(ofSize: 13, weight: .regular)

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
        if indexPath.row == 0 {
            return urlCell(textField: checkoutUrlTextField, label: "URL", imageName: "link")
        } else if indexPath.row == 1 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Open URL in Card"
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
            cell.textLabel?.textColor = .systemBlue
            cell.imageView?.image = systemImage("creditcard.fill")
            cell.imageView?.tintColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            return cell
        } else if indexPath.row == 2 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Generate Checkout"
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
            cell.textLabel?.textColor = .systemBlue
            cell.imageView?.image = systemImage("creditcard.fill")
            cell.imageView?.tintColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            return cell
        } else {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Open Webshop"
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
            cell.textLabel?.textColor = .systemBlue
            cell.imageView?.image = systemImage("storefront")
            cell.imageView?.tintColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }

    func modalSectionCell(for indexPath: IndexPath) -> UITableViewCell {
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
    }

    func browserSectionCell(for indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            return urlCell(textField: browserUrlTextField, label: "URL", imageName: "link")
        } else if indexPath.row == 1 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Open URL in Browser"
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
            cell.textLabel?.textColor = .systemBlue
            cell.imageView?.image = systemImage("safari")
            cell.imageView?.tintColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            return cell
        } else {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Generate Checkout"
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
            cell.textLabel?.textColor = .systemBlue
            cell.imageView?.image = systemImage("cart.fill")
            cell.imageView?.tintColor = .secondaryLabel
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }

    func checkoutGenerationCell(for indexPath: IndexPath) -> UITableViewCell {
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

    func gameSimulationCell(for indexPath: IndexPath) -> UITableViewCell {
        return switchCell(
            title: "Lock app to Landscape",
            subtitle: "Simulates a landscape-locked game engine",
            switchView: simulateLandscapeSwitch
        )
    }

    func urlCell(textField: UITextField, label: String, imageName: String) -> UITableViewCell {
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
                textField.heightAnchor.constraint(equalToConstant: 22)
            ])
        }
        return cell
    }

    func switchCell(title: String, subtitle: String?, switchView: UISwitch) -> UITableViewCell {
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

    func sliderCell(title: String, valueLabel: UILabel, slider: UISlider) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        let content = makeSliderCellContent(title: title, valueLabel: valueLabel, slider: slider)
        cell.contentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)
        ])
        return cell
    }
}
