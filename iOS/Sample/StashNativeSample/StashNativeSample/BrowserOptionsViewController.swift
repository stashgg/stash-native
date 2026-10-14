import UIKit
import StashNative

final class BrowserOptionsViewController: UITableViewController {
    private let config: StashNativeBrowserConfig

    init(config: StashNativeBrowserConfig) {
        self.config = config
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Browser options"
        navigationItem.largeTitleDisplayMode = .never
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 40
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        SampleSectionHeaderView("General")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.text = "Prefer portrait"
        cell.detailTextLabel?.text = "Request portrait where supported."
        cell.detailTextLabel?.numberOfLines = 0
        cell.detailTextLabel?.textColor = .secondaryLabel
        let toggle = UISwitch()
        toggle.isOn = config.orientationPreference == .portrait
        toggle.accessibilityIdentifier = "browser-prefer-portrait"
        toggle.accessibilityLabel = "Prefer portrait"
        toggle.addAction(UIAction { [weak self, weak toggle] _ in
            self?.config.orientationPreference = toggle?.isOn == true ? .portrait : .followHost
        }, for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }
}
