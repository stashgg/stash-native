import UIKit
import StashNative

final class CodeLinkOptionsViewController: UITableViewController {
    private let config: StashNativeCodeLinkConfig

    private enum TextField: Int {
        case header, title, subtitle, cameraUnavailable, connected

        var label: String {
            switch self {
            case .header: return "Header text"
            case .title: return "Callout title"
            case .subtitle: return "Callout subtitle"
            case .cameraUnavailable: return "Camera unavailable text"
            case .connected: return "Connected text"
            }
        }

        var defaultText: String {
            switch self {
            case .header: return "Scan QR code"
            case .title: return "Scan the webshop code"
            case .subtitle: return "Keep the QR code centered inside the frame."
            case .cameraUnavailable: return "Camera unavailable"
            case .connected: return "Connected"
            }
        }

        var keyPath: ReferenceWritableKeyPath<StashNativeCodeLinkConfig, String?> {
            switch self {
            case .header: return \.headerText
            case .title: return \.calloutTitle
            case .subtitle: return \.calloutSubtitle
            case .cameraUnavailable: return \.cameraUnavailableText
            case .connected: return \.connectedText
            }
        }
    }

    init(config: StashNativeCodeLinkConfig) {
        self.config = config
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "QR Code scan options"
        navigationItem.largeTitleDisplayMode = .never
        tableView.keyboardDismissMode = .onDrag
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 4 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 1: return 3
        case 2: return 2
        default: return 1
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Header"
        case 1: return "Info callout"
        case 2: return "Status text"
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 2 ? "Empty text uses the default wording. Changes apply to the next scan." : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        if indexPath.section == 3 {
            cell.textLabel?.text = "Reset to defaults"
            cell.textLabel?.textColor = .systemBlue
        } else if indexPath.section == 1 && indexPath.row == 0 {
            cell.textLabel?.text = "Show info callout"
            cell.selectionStyle = .none
            let toggle = UISwitch()
            toggle.isOn = config.showCallout
            toggle.accessibilityIdentifier = "code-link-show-callout"
            toggle.accessibilityLabel = "Show info callout"
            toggle.addAction(UIAction { [weak self, weak toggle] _ in
                self?.config.showCallout = toggle?.isOn ?? true
            }, for: .valueChanged)
            cell.accessoryView = toggle
        } else if let field = textField(at: indexPath) {
            return textCell(field)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 3 {
            config.headerText = nil
            config.calloutTitle = nil
            config.calloutSubtitle = nil
            config.cameraUnavailableText = nil
            config.connectedText = nil
            config.showCallout = true
            tableView.reloadData()
        }
    }

    private func textCell(_ field: TextField) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        let label = UILabel()
        label.text = field.label
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        let input = UITextField()
        input.text = config[keyPath: field.keyPath]
        input.placeholder = field.defaultText
        input.font = .preferredFont(forTextStyle: .body)
        input.adjustsFontForContentSizeCategory = true
        input.clearButtonMode = .whileEditing
        input.returnKeyType = .done
        input.accessibilityLabel = field.label
        input.accessibilityIdentifier = "code-link-text-\(field.rawValue)"
        input.addAction(UIAction { [weak self, weak input] _ in
            let text = input?.text ?? ""
            self?.config[keyPath: field.keyPath] = text.isEmpty ? nil : text
        }, for: .editingChanged)
        input.addAction(UIAction { [weak input] _ in
            input?.resignFirstResponder()
        }, for: .editingDidEndOnExit)
        let stack = UIStackView(arrangedSubviews: [label, input])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)
        ])
        return cell
    }

    private func textField(at indexPath: IndexPath) -> TextField? {
        if indexPath.section == 0 { return .header }
        if indexPath.section == 2 { return indexPath.row == 0 ? .cameraUnavailable : .connected }
        return indexPath.section == 1 && indexPath.row > 0 ? TextField(rawValue: indexPath.row) : nil
    }
}
