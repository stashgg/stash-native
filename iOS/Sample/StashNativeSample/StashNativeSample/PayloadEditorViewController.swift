//
//  PayloadEditorViewController.swift
//  StashNativeSample
//
//  Free-form editor for the JSON body sent to the checkout/webshop endpoints.
//

import UIKit

/// A pushed screen holding the raw request body for one endpoint. Whatever is saved here is sent
/// verbatim, so the text is deliberately unvalidated -- editing it is the point.
final class PayloadEditorViewController: UIViewController {

    private let kind: ViewController.PayloadKind
    private let instanceId: String
    private weak var host: ViewController?
    private let textView = UITextView()

    init(kind: ViewController.PayloadKind, instanceId: String, host: ViewController) {
        self.kind = kind
        self.instanceId = instanceId
        self.host = host
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = kind == .checkout ? "Edit Checkout Payload" : "Edit Webshop Payload"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        // Icon-only actions; titles stay as accessibility labels.
        let save = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.down"),
                                   style: .done, target: self, action: #selector(saveTapped))
        save.accessibilityLabel = "Save"
        let reset = UIBarButtonItem(image: UIImage(systemName: "arrow.counterclockwise"),
                                    style: .plain, target: self, action: #selector(resetTapped))
        reset.accessibilityLabel = "Reset"
        navigationItem.rightBarButtonItems = [save, reset]

        textView.text = host?.instancePayload(instanceId, kind) ?? ""
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
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
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            textView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])

        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardChanged(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    /// Keeps the caret clear of the keyboard while editing a long body.
    @objc private func keyboardChanged(_ note: Notification) {
        guard let window = view.window,
              let value = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
              note.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool ?? true else { return }
        // Keyboard frame is in screen space, not window space.
        let keyboard = window.screen.coordinateSpace.convert(
            value.cgRectValue, to: view.coordinateSpace)
        let overlap = textView.frame.maxY - keyboard.minY
        textView.contentInset.bottom = max(0, overlap)
        textView.verticalScrollIndicatorInsets.bottom = max(0, overlap)
    }

    @objc private func saveTapped() {
        host?.saveInstancePayload(instanceId, kind, textView.text ?? "")
        view.endEditing(true)
        let alert = UIAlertController(title: nil, message: "Payload saved", preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { alert.dismiss(animated: true) }
    }

    @objc private func resetTapped() {
        textView.text = ViewController.defaultPayload(kind)
    }
}
