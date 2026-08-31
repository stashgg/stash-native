//
//  SampleWindow.swift
//  StashNativeDesktopSample
//
//  One window: credentials, checkout URL and the three presentation modes, options, and the
//  event log. The window is also the host window the card is presented over.
//

import AppKit
import StashNativeDesktop

final class SampleWindow: NSWindow, StashNativeCardDelegate, NSTextFieldDelegate {
    private let appIdField = NSTextField()
    private let secretField = NSSecureTextField()
    private let environmentPopup = NSPopUpButton()
    private let urlField = NSTextField()
    private let autoCloseCheck = NSButton(checkboxWithTitle: "autoClose", target: nil, action: nil)
    private let allowDismissCheck = NSButton(checkboxWithTitle: "allowDismiss (modal)", target: nil, action: nil)
    private let windowCheck = NSButton(checkboxWithTitle: "Window presentation", target: nil, action: nil)
    private let inspectableCheck = NSButton(checkboxWithTitle: "Inspectable webview", target: nil, action: nil)
    private let backgroundField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "Ready")
    private let logView = NSTextView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered, defer: false)
        title = "Stash Native Desktop Sample \(StashNativeCard.sdkVersion())"
        minSize = NSSize(width: 560, height: 600)
        center()
        buildContent()
        StashNativeCard.sharedInstance().delegate = self
        EventLog.shared.onEvent = { [weak self] entry in
            self?.appendLog("event \(entry.summary)")
        }
    }

    // MARK: - Layout

    private func labeled(_ title: String, _ view: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let row = NSStackView(views: [label, view])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .rounded
        return btn
    }

    private func configureFields() {
        appIdField.placeholderString = "App ID"
        appIdField.stringValue = SampleSettings.appId
        appIdField.delegate = self
        secretField.placeholderString = "Ingress secret (base64)"
        secretField.stringValue = SampleSettings.ingressSecret
        secretField.delegate = self
        for env in StashEnvironment.allCases {
            environmentPopup.addItem(withTitle: env.title)
        }
        environmentPopup.selectItem(at: StashEnvironment.allCases.firstIndex(of: SampleSettings.environment) ?? 0)
        environmentPopup.target = self
        environmentPopup.action = #selector(settingsChanged)
        urlField.placeholderString = "https://checkout.stash.gg/pay/..."
        urlField.stringValue = SampleSettings.lastUrl
        urlField.delegate = self
        backgroundField.placeholderString = "#1e1e1e (optional)"
        autoCloseCheck.state = .on
        allowDismissCheck.state = .on
        inspectableCheck.target = self
        inspectableCheck.action = #selector(inspectableChanged)
        statusLabel.font = NSFont.boldSystemFont(ofSize: 12)
    }

    private func horizontalRow(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        return row
    }

    private func makeLogScrollView() -> NSScrollView {
        logView.isEditable = false
        logView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.autoresizingMask = [.width]
        let scroll = NSScrollView()
        scroll.documentView = logView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        return scroll
    }

    private func buildContent() {
        configureFields()
        let scroll = makeLogScrollView()
        let stack = NSStackView(views: [
            labeled("App ID", appIdField),
            labeled("Ingress secret", secretField),
            labeled("Environment", environmentPopup),
            button("Generate Checkout URL", #selector(generateUrl)),
            labeled("Checkout URL", urlField),
            horizontalRow([button("Open Card", #selector(openCard)),
                           button("Open Modal", #selector(openModal)),
                           button("Open Browser", #selector(openBrowser)),
                           button("Dismiss", #selector(dismissCard))]),
            horizontalRow([button("Local Test Page", #selector(openLocalPage)),
                           button("Validation Matrix", #selector(openMatrixPage)),
                           button("Clear Log", #selector(clearLog))]),
            horizontalRow([autoCloseCheck, allowDismissCheck, windowCheck, inspectableCheck]),
            labeled("Background", backgroundField),
            statusLabel,
            scroll
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        guard let content = contentView else { return }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -16),
            urlField.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -16),
            appIdField.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -16),
            secretField.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -16)
        ])
    }

    // MARK: - Actions

    func controlTextDidChange(_ obj: Notification) {
        settingsChanged()
    }

    @objc private func settingsChanged() {
        SampleSettings.appId = appIdField.stringValue
        SampleSettings.ingressSecret = secretField.stringValue
        SampleSettings.environment = StashEnvironment.allCases[max(0, environmentPopup.indexOfSelectedItem)]
        SampleSettings.lastUrl = urlField.stringValue
    }

    @objc private func inspectableChanged() {
        StashNativeCard.setInspectableWebViewsEnabled(inspectableCheck.state == .on)
    }

    private var configJSON: String {
        var fields = ["\"autoClose\":\(autoCloseCheck.state == .on)",
                      "\"allowDismiss\":\(allowDismissCheck.state == .on)",
                      "\"presentation\":\"\(windowCheck.state == .on ? "window" : "attached")\""]
        let background = backgroundField.stringValue.trimmingCharacters(in: .whitespaces)
        if !background.isEmpty {
            fields.append("\"backgroundColor\":\"\(background)\"")
        }
        return "{" + fields.joined(separator: ",") + "}"
    }

    private func localConfigJSON() -> String {
        String(configJSON.dropLast()) + ",\"allowFileUrls\":true}"
    }

    @objc private func generateUrl() {
        setStatus("Generating URL...")
        LinkGenerator.generateCheckoutUrl(environment: SampleSettings.environment,
                                          appId: SampleSettings.appId,
                                          ingressSecret: SampleSettings.ingressSecret,
                                          payload: SampleSettings.defaultCheckoutPayload) { [weak self] result in
            switch result {
            case .success(let url):
                self?.urlField.stringValue = url
                SampleSettings.lastUrl = url
                self?.setStatus("URL generated")
            case .failure(let error):
                self?.setStatus(error.message)
            }
        }
    }

    @objc private func openCard() {
        appendLog("openCard \(configJSON)")
        StashNativeCard.sharedInstance().openCard(withURL: urlField.stringValue, configJSON: configJSON)
    }

    @objc private func openModal() {
        appendLog("openModal \(configJSON)")
        StashNativeCard.sharedInstance().openModal(withURL: urlField.stringValue, configJSON: configJSON)
    }

    @objc private func openBrowser() {
        StashNativeCard.sharedInstance().openBrowser(withURL: urlField.stringValue)
    }

    @objc private func openLocalPage() {
        let url = ProofRunner.testPageUrl("stash_test_checkout.html")
        appendLog("openCard stash_test_checkout.html")
        StashNativeCard.sharedInstance().openCard(withURL: url, configJSON: localConfigJSON())
    }

    @objc private func openMatrixPage() {
        let url = ProofRunner.testPageUrl("stash_validation_matrix.html") + "?auto=1"
        appendLog("openCard stash_validation_matrix.html?auto=1")
        StashNativeCard.sharedInstance().openCard(withURL: url, configJSON: localConfigJSON())
    }

    @objc private func dismissCard() {
        StashNativeCard.sharedInstance().dismiss()
    }

    @objc private func clearLog() {
        EventLog.shared.clear()
        logView.string = ""
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    private func appendLog(_ line: String) {
        logView.string += line + "\n"
        logView.scrollToEndOfDocument(nil)
    }

    // MARK: - StashNativeCardDelegate

    func stashNativeCardDidCompletePayment(withOrder order: String?) {
        setStatus("Payment success: \(order ?? "(no order)")")
    }

    func stashNativeCardDidFailPayment() {
        setStatus("Payment failed")
    }

    func stashNativeCardDidDismiss() {
        setStatus("Dismissed")
    }

    func stashNativeCardDidReceiveOpt(in optinType: String) {
        setStatus("Opt-in: \(optinType)")
    }

    func stashNativeCardDidLoadPage(_ loadTimeMs: Double) {
        setStatus("Page loaded in \(Int(loadTimeMs)) ms")
    }

    func stashNativeCardDidEncounterNetworkError() {
        setStatus("Network error")
    }

    func stashNativeCardDidRequestExternalPayment(with url: String) {
        // The URL can carry session parameters: the status names the origin only.
        setStatus("External payment: \(EventLog.Entry.origin(of: url))")
    }
}
