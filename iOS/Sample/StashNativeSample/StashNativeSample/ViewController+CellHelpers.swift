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

    func presentationOptionCell(for indexPath: IndexPath) -> UITableViewCell {
        let row = indexPath.row
        let checkoutCount = isCheckoutAdvancedExpanded ? CheckoutOptionRow.allCases.count : 0
        let modalHeaderIndex = 1 + checkoutCount

        if row == 0 {
            return checkoutOptionsHeaderCell()
        }
        if isCheckoutAdvancedExpanded && row >= 1 && row < 1 + checkoutCount {
            return checkoutOptionRow(at: row)
        }
        if row == modalHeaderIndex {
            return modalOptionsHeaderCell()
        }
        if isModalAdvancedExpanded && row > modalHeaderIndex {
            return modalOptionRow(at: row, modalHeaderIndex: modalHeaderIndex)
        }
        return UITableViewCell()
    }

    private func checkoutOptionsHeaderCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = isCheckoutAdvancedExpanded ? "Hide Card options" : "Show Card options"
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        cell.textLabel?.textColor = .label
        cell.accessoryType = isCheckoutAdvancedExpanded ? .detailButton : .disclosureIndicator
        cell.imageView?.image = systemImage("slider.horizontal.3")
        cell.imageView?.tintColor = .secondaryLabel
        return cell
    }

    private func modalOptionsHeaderCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = isModalAdvancedExpanded ? "Hide Modal options" : "Show Modal options"
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        cell.textLabel?.textColor = .label
        cell.accessoryType = isModalAdvancedExpanded ? .detailButton : .disclosureIndicator
        cell.imageView?.image = systemImage("rectangle.inset.filled")
        cell.imageView?.tintColor = .secondaryLabel
        return cell
    }

    // swiftlint:disable:next function_body_length
    private func checkoutOptionRow(at row: Int) -> UITableViewCell {
        guard let checkoutRow = CheckoutOptionRow(rawValue: row - 1) else {
            return UITableViewCell()
        }
        switch checkoutRow {
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

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func modalOptionRow(at row: Int, modalHeaderIndex: Int) -> UITableViewCell {
        guard let modalRow = ModalOptionRow(rawValue: row - modalHeaderIndex - 1) else {
            return UITableViewCell()
        }
        switch modalRow {
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

    func handlePresentationOptionsSelection(at indexPath: IndexPath) {
        let checkoutCount = isCheckoutAdvancedExpanded ? CheckoutOptionRow.allCases.count : 0
        let modalHeaderIndex = 1 + checkoutCount
        if indexPath.row == 0 {
            checkoutOptionsToggleTapped()
        } else if indexPath.row == modalHeaderIndex {
            modalOptionsToggleTapped()
        }
    }

    func heightForPresentationOptionRow(at indexPath: IndexPath) -> CGFloat {
        let row = indexPath.row
        let checkoutCount = isCheckoutAdvancedExpanded ? CheckoutOptionRow.allCases.count : 0
        let modalHeaderIndex = 1 + checkoutCount
        if row > 0 && row < 1 + checkoutCount {
            guard let checkoutRow = CheckoutOptionRow(rawValue: row - 1) else {
                return UITableView.automaticDimension
            }
            switch checkoutRow {
            case .cardBackgroundHex:
                return 44
            case .phoneCardHeight, .phoneLandscapeWidth, .phoneLandscapeHeight,
                 .tabletPortraitWidth, .tabletPortraitHeight,
                 .tabletLandscapeWidth, .tabletLandscapeHeight:
                return 72
            default: return 44
            }
        }
        if row > modalHeaderIndex {
            guard let modalRow = ModalOptionRow(rawValue: row - modalHeaderIndex - 1) else {
                return UITableView.automaticDimension
            }
            switch modalRow {
            case .modalBackgroundHex:
                return 44
            case .modalPhonePortraitWidth, .modalPhonePortraitHeight,
                 .modalPhoneLandscapeWidth, .modalPhoneLandscapeHeight,
                 .modalTabletPortraitWidth, .modalTabletPortraitHeight,
                 .modalTabletLandscapeWidth, .modalTabletLandscapeHeight:
                return 72
            default: return 44
            }
        }
        return 44
    }
}
