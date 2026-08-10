//
//  ViewController+CellHelpers.swift
//  StashNativeSample
//
//  Helper methods for creating table view cells.
//

import UIKit

// MARK: - Cell Creation Helpers

extension ViewController {

    /// Text-only action button row (no icon, no chevron).
    func actionCell(_ title: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        cell.textLabel?.textColor = .systemBlue
        return cell
    }

    func cardSectionCell(for indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.row {
        case 0: return urlCell(textField: checkoutUrlTextField, label: "URL", imageName: "link",
                               openSelector: #selector(openCardTapped))
        case 1: return actionCell("Generate Checkout")
        default: return actionCell("Open Webshop")
        }
    }

    func modalSectionCell() -> UITableViewCell {
        return urlCell(textField: modalUrlTextField, label: "URL", imageName: "link",
                       openSelector: #selector(openModalTapped))
    }

    func browserSectionCell(for indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.row {
        case 0: return urlCell(textField: browserUrlTextField, label: "URL", imageName: "link",
                               openSelector: #selector(openBrowserTapped))
        case 1: return actionCell("Generate Checkout")
        default: return actionCell("Open Webshop")
        }
    }

    func checkoutGenerationCell(for indexPath: IndexPath) -> UITableViewCell {
        apiKeyCell(apiKeys[indexPath.row], at: indexPath.row)
    }

    /// Instance row: the leading radio selects the active instance; tapping the row (disclosure)
    /// opens its details. Two separate tap targets, so the button's `tag` carries the row.
    private func apiKeyCell(_ entry: ApiKeyEntry, at row: Int) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        cell.accessoryType = .disclosureIndicator

        let isSelected = entry.id == selectedApiKeyId
        let radio = UIButton(type: .system)
        radio.setImage(systemImage(isSelected ? "checkmark.circle.fill" : "circle"), for: .normal)
        radio.tintColor = isSelected ? .systemBlue : .tertiaryLabel
        radio.tag = row
        radio.accessibilityLabel = "Select instance"
        radio.addTarget(self, action: #selector(instanceRadioTapped(_:)), for: .touchUpInside)
        radio.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = UILabel()
        nameLabel.text = entry.name
        nameLabel.font = .systemFont(ofSize: 17, weight: .regular)
        nameLabel.textColor = .label
        let modeLabel = UILabel()
        modeLabel.text = entry.production ? "Production" : "Test"
        modeLabel.font = .systemFont(ofSize: 13, weight: .regular)
        modeLabel.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [nameLabel, modeLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        cell.contentView.addSubview(radio)
        cell.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            radio.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            radio.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            radio.widthAnchor.constraint(equalToConstant: 30),
            radio.heightAnchor.constraint(equalToConstant: 30),
            stack.leadingAnchor.constraint(equalTo: radio.trailingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.contentView.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -10)
        ])
        return cell
    }

    /// URL entry row. When `openSelector` is set, an inline "Open" button sits at the trailing
    /// edge and the text field shrinks to make room.
    func urlCell(textField: UITextField, label: String, imageName: String,
                 openSelector: Selector? = nil) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.text = label
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        cell.textLabel?.textColor = .label
        cell.imageView?.image = systemImage(imageName)
        cell.imageView?.tintColor = .secondaryLabel
        cell.detailTextLabel?.text = nil

        // Cells are recreated each time, so move the shared field into this cell's contentView.
        textField.removeFromSuperview()
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(textField)

        var fieldTrailing = cell.contentView.trailingAnchor
        var fieldTrailingConstant: CGFloat = -36
        if let openSelector = openSelector {
            let openButton = UIButton(type: .system)
            openButton.setImage(UIImage(systemName: "chevron.right",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)),
                for: .normal)
            openButton.tintColor = .systemBlue
            openButton.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
            openButton.layer.cornerRadius = 15
            openButton.addTarget(self, action: openSelector, for: .touchUpInside)
            // Derive a stable id from the field, e.g. card-url-field -> card-open-button.
            openButton.accessibilityIdentifier =
                textField.accessibilityIdentifier?.replacingOccurrences(
                    of: "-url-field", with: "-open-button")
            openButton.translatesAutoresizingMaskIntoConstraints = false
            openButton.setContentHuggingPriority(.required, for: .horizontal)
            openButton.setContentCompressionResistancePriority(.required, for: .horizontal)
            cell.contentView.addSubview(openButton)
            NSLayoutConstraint.activate([
                openButton.widthAnchor.constraint(equalToConstant: 30),
                openButton.heightAnchor.constraint(equalToConstant: 30),
                openButton.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                openButton.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
            ])
            fieldTrailing = openButton.leadingAnchor
            fieldTrailingConstant = -8
        }

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 120),
            textField.trailingAnchor.constraint(equalTo: fieldTrailing, constant: fieldTrailingConstant),
            textField.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor)
        ])
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
