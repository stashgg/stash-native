//
//  InstancesTransferViewController.swift
//  StashNativeSample
//
//  Import/export sheet for instances.
//

import UIKit
import UniformTypeIdentifiers

/// One text view serves both directions: it opens holding the exported document (copy it out),
/// and Import reads back whatever is in it. The format is shared with the Android sample.
final class InstancesTransferViewController: UIViewController {

    private weak var host: ViewController?
    private let textView = UITextView()

    init(host: ViewController) {
        self.host = host
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Import / Export"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(closeTapped))
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Import", style: .done, target: self,
                            action: #selector(importTapped)),
            UIBarButtonItem(title: "Copy", style: .plain, target: self,
                            action: #selector(copyTapped))
        ]

        textView.text = host?.exportInstancesJson() ?? "{}"
        textView.font = UIFontMetrics(forTextStyle: .caption1)
            .scaledFont(for: .monospacedSystemFont(ofSize: 12, weight: .regular))
        textView.adjustsFontForContentSizeCategory = true
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.backgroundColor = .secondarySystemGroupedBackground
        textView.layer.cornerRadius = 10
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            textView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func copyTapped() {
        // The document carries ingress secrets: keep it off Universal Clipboard and expire it.
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: textView.text ?? ""]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
        flash("Copied to clipboard")
    }

    @objc private func importTapped() {
        view.endEditing(true)
        guard let result = host?.importInstancesJson(textView.text ?? "") else {
            flash("Could not read that document")
            return
        }
        if result.added == 0 {
            flash("No new instances to import")
            return
        }
        if !result.saved {
            let alert = UIAlertController(title: "Could not save instances",
                message: "Imported \(result.added) instance(s) for this session only.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        // Match the Android sample: a successful import drops back to the refreshed list.
        flash("Imported \(result.added) instance(s)") { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    private func flash(_ message: String, then completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            alert.dismiss(animated: true, completion: completion)
        }
    }
}
