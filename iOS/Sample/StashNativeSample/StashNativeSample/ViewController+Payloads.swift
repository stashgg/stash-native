//
//  ViewController+Payloads.swift
//  StashNativeSample
//
//  Editable request bodies for the two endpoints.
//

import UIKit

extension ViewController {

    // Payloads are per-instance (see ApiKeyEntry). The editor sends whatever text the user saves,
    // verbatim; these defaults are the test fixtures seeded into every new instance.

    enum PayloadKind { case checkout, webshop }

    static func defaultPayload(_ kind: PayloadKind) -> String {
        kind == .checkout ? defaultCheckoutPayload : defaultWebshopPayload
    }

    /// Default body for /sdk/server/checkout_links/generate_quick_pay_url.
    static let defaultCheckoutPayload = """
    {
      "user": {
        "id": "7849fbc5-87fd-446d-8d9c-de25298f1092",
        "validatedEmail": "test@stash.gg",
        "displayName": "Test User",
        "profileImageUrl": "https://storage.googleapis.com/stash-demo-f9550.firebasestorage.app\
    /avatars/6564ced3-c163-4b0d-aa4e-c1a19e42aa65.png",
        "platform": "IOS"
      },
      "item": {
        "id": "realMoneyProduct_gems_001",
        "name": "Handful of Blackstone",
        "pricePerItem": "1.99",
        "quantity": 1,
        "imageUrl": "https://static.stash.gg/stash_logo_128.png"
      },
      "currency": "USD",
      "createPaymentIntent": true,
      "transactionId": "6ef37116-e16f-43c6-ac72-8741c0bbd2b5",
      "regionCode": "US",
      "bonusItems": [
        {
          "id": "196492b7-78f1-4875-bfb5-ff612b46c1f9",
          "name": "Bonus Item",
          "imageUrl": "https://static.stash.gg/stash_logo_128.png",
          "quantity": 1
        }
      ]
    }
    """

    /// Default body for /sdk/server/generate_url.
    static let defaultWebshopPayload = """
    {
      "user": {
        "id": "7849fbc5-87fd-446d-8d9c-de25298f1092",
        "validatedEmail": "test@stash.gg",
        "displayName": "Test User",
        "platform": "IOS"
      },
      "target": "STORE"
    }
    """

}
