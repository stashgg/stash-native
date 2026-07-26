//
//  InstanceDetailViewController.swift
//  StashNativeSample
//
//  Editable details for one instance: name, app ID, ingress secret, environment, its
//  per-instance checkout/webshop payloads, and a destructive delete action.
//

import UIKit

/// A pushed screen for editing a single instance. Identity fields commit into the host's in-memory
/// model as the user types and are persisted immediately; the payload editors (pushed from here)
/// persist on their own Save. Rows reuse the app's shared cell styling so the screen matches the
/// Test and options screens.
final class InstanceDetailViewController: UITableViewController, UITextFieldDelegate {

    private weak var host: ViewController?
    private let instanceId: String

    private let nameField = UITextField()
    private let appIdField = UITextField()
    private let secretField = UITextField()
    private let productionSwitch = UISwitch()

    private enum Section: Int, CaseIterable { case instance, payloads, delete }
    private enum DetailRow { case name, appId, secret, production }
    private let detailRows: [DetailRow] = [.name, .appId, .secret, .production]

    init(host: ViewController, instanceId: String) {
        self.host = host
        self.instanceId = instanceId
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Edit Instance"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        tableView.keyboardDismissMode = .onDrag
        tableView.estimatedRowHeight = 56
        tableView.estimatedSectionHeaderHeight = 40

        let entry = host?.instance(withId: instanceId)
        configureField(nameField, text: entry?.name ?? "", placeholder: "Name")
        nameField.autocapitalizationType = .words
        configureField(appIdField, text: entry?.appId ?? "", placeholder: "App ID")
        configureField(secretField, text: entry?.key ?? "", placeholder: "Ingress secret")
        productionSwitch.isOn = entry?.production ?? false

        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        appIdField.addTarget(self, action: #selector(appIdChanged), for: .editingChanged)
        secretField.addTarget(self, action: #selector(secretChanged), for: .editingChanged)
        productionSwitch.addTarget(self, action: #selector(productionChanged), for: .valueChanged)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Commit any in-flight edit and refresh the list.
        view.endEditing(true)
        host?.persistInstances()
    }

    private func configureField(_ field: UITextField, text: String, placeholder: String) {
        field.text = text
        field.placeholder = placeholder
        field.font = .systemFont(ofSize: 17, weight: .regular)
        field.textColor = .label
        field.textAlignment = .right
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        field.delegate = self
    }

    @objc private func nameChanged() { host?.setInstanceName(instanceId, nameField.text ?? "") }
    @objc private func appIdChanged() { host?.setInstanceAppId(instanceId, appIdField.text ?? "") }
    @objc private func secretChanged() { host?.setInstanceSecret(instanceId, secretField.text ?? "") }
    @objc private func productionChanged() {
        host?.setInstanceProduction(instanceId, productionSwitch.isOn)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    // MARK: - Table

    override func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section) {
        case .instance: return detailRows.count
        case .payloads: return 2
        default: return 1
        }
    }

    // Custom header matching the app's other screens (13pt semibold, secondary), rather than the
    // default grouped header, whose size differs.
    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let title: String
        switch Section(rawValue: section) {
        case .instance: title = "INSTANCE"
        case .payloads: title = "TEST PAYLOADS"
        default: return nil
        }
        let label = UILabel()
        label.text = title
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

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        Section(rawValue: section) == .delete ? 20 : UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section) {
        case .instance:
            switch detailRows[indexPath.row] {
            case .name: return fieldCell(label: "Name", icon: "person", field: nameField)
            case .appId: return fieldCell(label: "App ID", icon: "number", field: appIdField)
            case .secret: return fieldCell(label: "Ingress secret", icon: "key", field: secretField)
            case .production:
                return host?.switchCell(title: "Production", subtitle: nil, switchView: productionSwitch)
                    ?? UITableViewCell()
            }
        case .payloads:
            return navCell(indexPath.row == 0 ? "Edit Checkout Payload" : "Edit Webshop Payload")
        default:
            return deleteCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section) {
        case .payloads:
            guard let host = host else { return }
            navigationController?.pushViewController(
                PayloadEditorViewController(
                    kind: indexPath.row == 0 ? .checkout : .webshop,
                    instanceId: instanceId, host: host),
                animated: true)
        case .delete:
            confirmDelete()
        default:
            break
        }
    }

    private func confirmDelete() {
        let alert = UIAlertController(
            title: "Delete instance?", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            self.host?.deleteApiKey(self.instanceId)
            self.navigationController?.popViewController(animated: true)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        // Anchor for iPad's popover presentation.
        if let popover = alert.popoverPresentationController {
            let deletePath = IndexPath(row: 0, section: Section.delete.rawValue)
            popover.sourceView = tableView.cellForRow(at: deletePath) ?? tableView
            popover.sourceRect = (tableView.cellForRow(at: deletePath) ?? tableView).bounds
        }
        present(alert, animated: true)
    }

    // MARK: - Cells

    /// Icon + label + right-aligned editable value, matching the app's URL/background rows.
    private func fieldCell(label: String, icon: String, field: UITextField) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        let iconView = UIImageView(image: host?.systemImage(icon))
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .center
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        let title = UILabel()
        title.text = label
        title.font = .systemFont(ofSize: 17, weight: .regular)
        title.textColor = .label
        title.setContentHuggingPriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        field.translatesAutoresizingMaskIntoConstraints = false
        let row = UIStackView(arrangedSubviews: [iconView, title, field])
        row.axis = .horizontal
        row.spacing = 16
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(row)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 24),
            row.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -20),
            row.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            row.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)
        ])
        return cell
    }

    private func navCell(_ title: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        cell.textLabel?.textColor = .label
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func deleteCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = "Delete Instance"
        cell.textLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        cell.textLabel?.textColor = .systemRed
        cell.textLabel?.textAlignment = .center
        return cell
    }
}
