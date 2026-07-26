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
        visibleSections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = visibleSection(at: section) else { return 0 }
        switch sectionType {
        case .card: return 3
        case .modal: return 1
        case .browser: return 3
        case .presentationOptions: return 2
        case .other: return 1
        case .about: return 1
        case .checkoutGenerationSettings: return apiKeys.count
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let sectionType = visibleSection(at: section) else { return nil }
        let title: String?
        switch sectionType {
        case .card: title = "CARD"
        case .modal: title = "MODAL"
        case .browser: title = "BROWSER"
        case .presentationOptions: title = "PRESENTATION OPTIONS"
        case .other: title = "OTHER"
        case .about: title = "ABOUT"
        case .checkoutGenerationSettings: title = "INSTANCES"
        }
        guard let titleText = title else { return nil }
        let label = UILabel()
        label.text = titleText
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
        ])
        return container
    }

    // No footers; 0 kills the grouped-style inter-section gap.
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sectionType = visibleSection(at: indexPath.section) else {
            return UITableViewCell()
        }
        switch sectionType {
        case .card:
            return cardSectionCell(for: indexPath)
        case .modal:
            return modalSectionCell()
        case .browser:
            return browserSectionCell(for: indexPath)
        case .presentationOptions:
            return presentationOptionCell(for: indexPath)
        case .other:
            return otherCell()
        case .about:
            return aboutCell()
        case .checkoutGenerationSettings:
            return checkoutGenerationCell(for: indexPath)
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let sectionType = visibleSection(at: indexPath.section) else { return }
        switch sectionType {
        case .card where indexPath.row == 1:
            generateCheckoutTapped()
        case .card where indexPath.row == 2:
            openWebshopTapped()
        case .browser where indexPath.row == 1:
            generateCheckoutForBrowserTapped()
        case .browser where indexPath.row == 2:
            openWebshopForBrowserTapped()
        case .presentationOptions:
            handlePresentationOptionsSelection(at: indexPath)
        case .checkoutGenerationSettings:
            guard indexPath.row < apiKeys.count else { return }
            navigationController?.pushViewController(
                InstanceDetailViewController(host: self, instanceId: apiKeys[indexPath.row].id),
                animated: true)
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        44
    }
}

// MARK: - UITabBarDelegate

extension ViewController: UITabBarDelegate {
    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        currentTab = Tab(rawValue: item.tag) ?? .test
        applyHeader(for: currentTab)
        tableView.reloadData()
        tableView.setContentOffset(
            CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
    }

    /// Test shows the left-aligned Stash wordmark; the other tabs use a text title.
    func applyHeader(for tab: Tab) {
        switch tab {
        case .test:
            title = nil
            navigationItem.leftBarButtonItem = logoBarItem
        case .settings:
            title = "Settings"
            navigationItem.leftBarButtonItem = nil
        case .api:
            title = "Instances"
            navigationItem.leftBarButtonItem = nil
        }
        // Add + import/export belong to the Instances tab only (add sits at the trailing edge).
        navigationItem.rightBarButtonItems = tab == .api
            ? [addInstanceBarItem, instancesTransferBarItem] : nil
    }
}
