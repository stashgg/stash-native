//
//  ApiKeyEntry.swift
//  StashNativeSample
//
//  A saved Stash app credential.
//

import UIKit

struct ApiKeyEntry: Codable {
    let id: String
    var name: String
    /// Stash app ID (Studio -> Project Settings -> App details); goes in the signature header.
    var appId: String
    /// Base64 ingress secret (Studio -> Project Settings -> API Secrets); the HMAC key.
    var key: String
    var production: Bool
    /// Raw JSON body sent to the checkout endpoint for this instance.
    var checkoutPayload: String
    /// Raw JSON body sent to the webshop endpoint for this instance.
    var webshopPayload: String

    init(id: String, name: String, appId: String, key: String, production: Bool,
         checkoutPayload: String, webshopPayload: String) {
        self.id = id
        self.name = name
        self.appId = appId
        self.key = key
        self.production = production
        self.checkoutPayload = checkoutPayload
        self.webshopPayload = webshopPayload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        // Entries saved before HMAC signing carry no appId.
        appId = try container.decodeIfPresent(String.self, forKey: .appId) ?? ""
        key = try container.decode(String.self, forKey: .key)
        production = try container.decode(Bool.self, forKey: .production)
        // Entries saved before per-instance payloads carry none; loadApiKeys fills the defaults.
        checkoutPayload = try container.decodeIfPresent(String.self, forKey: .checkoutPayload) ?? ""
        webshopPayload = try container.decodeIfPresent(String.self, forKey: .webshopPayload) ?? ""
    }
}
