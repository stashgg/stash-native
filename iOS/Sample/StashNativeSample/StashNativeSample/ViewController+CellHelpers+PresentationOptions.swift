//
//  ViewController+CellHelpers+PresentationOptions.swift
//  StashNativeSample
//
//  Presentation options section cells and row heights for the sample table.
//

import UIKit

extension ViewController {

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
