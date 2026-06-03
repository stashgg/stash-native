//
//  ViewController+TableView.swift
//  StashNativeSample
//
//  TableView DataSource and Delegate implementation for ViewController.
//

import UIKit

// MARK: - UITableViewDataSource, UITableViewDelegate

extension ViewController {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = Section(rawValue: section) else { return 0 }
        switch sectionType {
        case .card: return 4
        case .modal: return 2
        case .browser: return 3
        case .presentationOptions:
            return 1 + (isCheckoutAdvancedExpanded ? CheckoutOptionRow.allCases.count : 0)
                + 1 + (isModalAdvancedExpanded ? ModalOptionRow.allCases.count : 0)
        case .checkoutGenerationSettings: return 2
        case .gameSimulation: return 1
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let sectionType = Section(rawValue: section) else { return nil }
        let title: String?
        switch sectionType {
        case .card: title = "CARD"
        case .modal: title = "MODAL"
        case .browser: title = "BROWSER"
        case .presentationOptions: title = "PRESENTATION OPTIONS"
        case .checkoutGenerationSettings: title = "CHECKOUT GENERATION SETTINGS"
        case .gameSimulation: title = "GAME ENGINE SIMULATION"
        }
        guard let titleText = title else { return nil }
        let label = UILabel()
        label.text = titleText
        label.font = Layout.sectionHeaderFont
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.contentInset),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.contentInset),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard let sectionType = Section(rawValue: section),
              let footerTextContent = footerText(for: sectionType) else { return nil }
        let label = UILabel()
        label.text = footerTextContent
        label.font = Layout.subtitleFont
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.contentInset),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.contentInset),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18)
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        guard let sectionType = Section(rawValue: section),
              let text = footerText(for: sectionType) else { return 0 }
        let width = tableView.bounds.width - 2 * Layout.contentInset
        if width <= 0 { return Layout.standardRowHeight }
        let rect = text.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: [.font: Layout.subtitleFont],
            context: nil
        )
        return ceil(rect.height) + 24
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sectionType = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }
        switch sectionType {
        case .card:
            return cardSectionCell(for: indexPath)
        case .modal:
            return modalSectionCell(for: indexPath)
        case .browser:
            return browserSectionCell(for: indexPath)
        case .presentationOptions:
            return presentationOptionCell(for: indexPath)
        case .checkoutGenerationSettings:
            return checkoutGenerationCell(for: indexPath)
        case .gameSimulation:
            return gameSimulationCell(for: indexPath)
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let sectionType = Section(rawValue: indexPath.section) else { return }
        switch sectionType {
        case .card where indexPath.row == 1:
            openCardTapped()
        case .card where indexPath.row == 2:
            generateCheckoutTapped()
        case .card where indexPath.row == 3:
            openWebshopTapped()
        case .modal where indexPath.row == 1:
            openModalTapped()
        case .browser where indexPath.row == 1:
            openBrowserTapped()
        case .browser where indexPath.row == 2:
            generateCheckoutForBrowserTapped()
        case .presentationOptions:
            handlePresentationOptionsSelection(at: indexPath)
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let sectionType = Section(rawValue: indexPath.section) else {
            return UITableView.automaticDimension
        }
        switch sectionType {
        case .presentationOptions:
            return heightForPresentationOptionRow(at: indexPath)
        default: break
        }
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        Layout.standardRowHeight
    }
}
