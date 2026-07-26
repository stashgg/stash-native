//
//  ViewController+Instances.swift
//  StashNativeSample
//
//  Saved instances: CRUD plus portable import/export.
//

import UIKit

extension ViewController {

    func loadApiKeys() {
        let payload = ApiKeyStore.load()
        apiKeys = payload.keys
        selectedApiKeyId = payload.selectedId
        if apiKeys.isEmpty {
            apiKeys = [ViewController.bundledEntry()]
        }
        // Migrate instances still holding a superseded bundled secret up to the current demo
        // credential. Only superseded secrets migrate, so name/app ID/secret edits the user makes
        // to the current bundled instance in its details screen are preserved across launches.
        for index in apiKeys.indices
        where ViewController.isSupersededBundledSecret(apiKeys[index].key) {
            apiKeys[index].name = ViewController.defaultStashKeyName
            apiKeys[index].appId = ViewController.defaultStashAppId
            apiKeys[index].key = ViewController.defaultStashApiKey
        }
        // Entries saved before per-instance payloads have none; seed them with the defaults.
        for index in apiKeys.indices {
            if apiKeys[index].checkoutPayload.isEmpty {
                apiKeys[index].checkoutPayload = ViewController.defaultCheckoutPayload
            }
            if apiKeys[index].webshopPayload.isEmpty {
                apiKeys[index].webshopPayload = ViewController.defaultWebshopPayload
            }
        }
        if selectedApiKeyId == nil || !apiKeys.contains(where: { $0.id == selectedApiKeyId }) {
            selectedApiKeyId = apiKeys.first?.id
        }
        saveApiKeys()
    }

    func saveApiKeys() {
        ApiKeyStore.save(keys: apiKeys, selectedId: selectedApiKeyId)
    }

    var selectedApiKey: ApiKeyEntry? {
        apiKeys.first(where: { $0.id == selectedApiKeyId })
    }

    // MARK: - Instance import/export
    // Deliberately platform-neutral: same field names and types as the Android sample, so
    // instances exported on either platform import on the other, per-instance payloads included.
    // Key order and colon spacing differ between the two serializers -- both importers read by
    // name and tolerate missing payload fields. Local ids are omitted; they are per-device and
    // regenerated on import.

    private static let instancesExportVersion = 2

    /// Every instance as a portable JSON document.
    func exportInstancesJson() -> String {
        let instances: [[String: Any]] = apiKeys.map {
            ["name": $0.name, "appId": $0.appId, "ingressSecret": $0.key, "production": $0.production,
             "checkoutPayload": $0.checkoutPayload, "webshopPayload": $0.webshopPayload]
        }
        let root: [String: Any] = [
            "version": ViewController.instancesExportVersion,
            "instances": instances
        ]
        guard let data = try? JSONSerialization.data(
                withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        // Match Android's output, which unescapes the '/' that can appear in base64 secrets.
        return text.replacingOccurrences(of: "\\/", with: "/")
    }

    /// Adds instances from an exported document, skipping any already present.
    /// Returns the number added, or nil if the document could not be read.
    func importInstancesJson(_ text: String) -> Int? {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let instances = root["instances"] as? [[String: Any]] else { return nil }
        var added = 0
        for entry in instances {
            let appId = (entry["appId"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let secret = (entry["ingressSecret"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if appId.isEmpty || secret.isEmpty
                || apiKeys.contains(where: { $0.appId == appId && $0.key == secret }) { continue }
            let name = (entry["name"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let checkout = entry["checkoutPayload"] as? String ?? ""
            let webshop = entry["webshopPayload"] as? String ?? ""
            apiKeys.append(ApiKeyEntry(
                id: UUID().uuidString, name: name.isEmpty ? "Untitled" : name,
                appId: appId, key: secret, production: entry["production"] as? Bool ?? false,
                checkoutPayload: checkout.isEmpty ? ViewController.defaultCheckoutPayload : checkout,
                webshopPayload: webshop.isEmpty ? ViewController.defaultWebshopPayload : webshop))
            added += 1
        }
        if added > 0 {
            saveApiKeys()
            reloadApiSection()
        }
        return added
    }

    /// Credential the API calls sign with: the selected entry, or the bundled demo one if the
    /// entry cannot sign (e.g. saved before HMAC signing, so it has no app ID). Secret, app ID
    /// and environment all come from one entry so they can never be mixed across credentials.
    private func activeEntry() -> ApiKeyEntry {
        guard let entry = selectedApiKey,
              !entry.appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !entry.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ViewController.bundledEntry()
        }
        return entry
    }

    /// Active ingress secret used to sign requests.
    func activeApiKey() -> String {
        activeEntry().key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Active app ID carried in the signature header.
    func activeAppId() -> String {
        activeEntry().appId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isActiveKeyProduction() -> Bool {
        activeEntry().production
    }

    /// Request body the active instance signs and sends for `kind`, verbatim.
    func activePayload(_ kind: PayloadKind) -> String {
        kind == .checkout ? activeEntry().checkoutPayload : activeEntry().webshopPayload
    }

    func selectApiKey(_ id: String) {
        guard apiKeys.contains(where: { $0.id == id }) else { return }
        selectedApiKeyId = id
        saveApiKeys()
        reloadApiSection()
    }

    /// The leading radio on an instance row selects it as the active instance.
    @objc func instanceRadioTapped(_ sender: UIButton) {
        guard sender.tag >= 0, sender.tag < apiKeys.count else { return }
        selectApiKey(apiKeys[sender.tag].id)
    }

    // MARK: - Instance details

    func instance(withId id: String) -> ApiKeyEntry? {
        apiKeys.first(where: { $0.id == id })
    }

    // Detail fields commit into the in-memory model as the user types; persistInstances()
    // writes them to the Keychain when the details screen is dismissed.
    // Detail fields commit and persist as the user types (parity with Android), so an edit is
    // never lost if the app is killed before the details screen closes.
    func setInstanceName(_ id: String, _ value: String) {
        guard let index = apiKeys.firstIndex(where: { $0.id == id }) else { return }
        apiKeys[index].name = value
        saveApiKeys()
    }

    func setInstanceAppId(_ id: String, _ value: String) {
        guard let index = apiKeys.firstIndex(where: { $0.id == id }) else { return }
        apiKeys[index].appId = value
        saveApiKeys()
    }

    func setInstanceSecret(_ id: String, _ value: String) {
        guard let index = apiKeys.firstIndex(where: { $0.id == id }) else { return }
        apiKeys[index].key = value
        saveApiKeys()
    }

    func setInstanceProduction(_ id: String, _ value: Bool) {
        guard let index = apiKeys.firstIndex(where: { $0.id == id }) else { return }
        apiKeys[index].production = value
        saveApiKeys()
    }

    /// Refreshes the instances list to reflect edits; call when the details screen closes.
    func persistInstances() {
        saveApiKeys()
        reloadApiSection()
    }

    func instancePayload(_ id: String, _ kind: PayloadKind) -> String {
        guard let entry = instance(withId: id) else { return ViewController.defaultPayload(kind) }
        return kind == .checkout ? entry.checkoutPayload : entry.webshopPayload
    }

    func saveInstancePayload(_ id: String, _ kind: PayloadKind, _ text: String) {
        guard let index = apiKeys.firstIndex(where: { $0.id == id }) else { return }
        if kind == .checkout {
            apiKeys[index].checkoutPayload = text
        } else {
            apiKeys[index].webshopPayload = text
        }
        saveApiKeys()
    }

    /// Returns false when the entry cannot sign; both app ID and secret are required.
    @discardableResult
    func addApiKey(name: String, appId: String, key: String, production: Bool) -> Bool {
        let cleanAppId = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanAppId.isEmpty, !cleanKey.isEmpty else { return false }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = ApiKeyEntry(
            id: UUID().uuidString,
            name: cleanName.isEmpty ? "Untitled" : cleanName,
            appId: cleanAppId,
            key: cleanKey,
            production: production,
            checkoutPayload: ViewController.defaultCheckoutPayload,
            webshopPayload: ViewController.defaultWebshopPayload)
        apiKeys.append(entry)
        selectedApiKeyId = entry.id
        saveApiKeys()
        reloadApiSection()
        return true
    }

    func deleteApiKey(_ id: String) {
        apiKeys.removeAll { $0.id == id }
        if apiKeys.isEmpty {
            apiKeys = [ViewController.bundledEntry()]
        }
        if !apiKeys.contains(where: { $0.id == selectedApiKeyId }) {
            selectedApiKeyId = apiKeys.first?.id
        }
        saveApiKeys()
        reloadApiSection()
    }

    private func reloadApiSection() {
        if currentTab == .api, let index = visibleSections.firstIndex(of: .checkoutGenerationSettings) {
            tableView.reloadSections(IndexSet(integer: index), with: .none)
        } else {
            tableView.reloadData()
        }
    }

    func showAddApiKey() {
        let alert = UIAlertController(title: "Add Instance", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Name" }
        alert.addTextField {
            $0.placeholder = "App ID"
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }
        alert.addTextField {
            $0.placeholder = "Ingress secret"
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }
        let add: (Bool) -> Void = { [weak self, weak alert] production in
            guard let self = self, let fields = alert?.textFields, fields.count >= 3 else { return }
            let added = self.addApiKey(name: fields[0].text ?? "",
                                       appId: fields[1].text ?? "",
                                       key: fields[2].text ?? "",
                                       production: production)
            if !added {
                self.showAlert(title: "Error",
                               message: "App ID and ingress secret are both required")
            }
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add as Test", style: .default) { _ in add(false) })
        alert.addAction(UIAlertAction(title: "Add as Production", style: .default) { _ in add(true) })
        present(alert, animated: true)
    }

}
