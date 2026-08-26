//
//  SampleSettings.swift
//  StashNativeDesktopSample
//
//  Credentials and last-used values. UserDefaults keeps a rebuilt, unsigned sample binary away
//  from Keychain prompts; the ingress secret is a server secret that must never ship in a real
//  client, so nothing here is production guidance.
//

import Foundation

enum StashEnvironment: String, CaseIterable {
    case test
    case production
    case staging

    var title: String {
        switch self {
        case .test: return "Test (test-api.stash.gg)"
        case .production: return "Production (api.stash.gg)"
        case .staging: return "Staging (test-api.stashstaging.com)"
        }
    }

    var apiBaseUrl: String {
        switch self {
        case .test: return "https://test-api.stash.gg"
        case .production: return "https://api.stash.gg"
        case .staging: return "https://test-api.stashstaging.com"
        }
    }
}

enum SampleSettings {
    private static let defaults = UserDefaults.standard

    static var appId: String {
        get { defaults.string(forKey: "stash.appId") ?? "" }
        set { defaults.set(newValue, forKey: "stash.appId") }
    }

    static var ingressSecret: String {
        get { defaults.string(forKey: "stash.ingressSecret") ?? "" }
        set { defaults.set(newValue, forKey: "stash.ingressSecret") }
    }

    static var environment: StashEnvironment {
        get { StashEnvironment(rawValue: defaults.string(forKey: "stash.environment") ?? "") ?? .test }
        set { defaults.set(newValue.rawValue, forKey: "stash.environment") }
    }

    static var lastUrl: String {
        get { defaults.string(forKey: "stash.lastUrl") ?? "" }
        set { defaults.set(newValue, forKey: "stash.lastUrl") }
    }

    /// Default body for /sdk/server/checkout_links/generate_quick_pay_url. No `platform`: the enum
    /// only knows IOS / ANDROID and desktop is correctly UNDEFINED. Saved payment methods are keyed
    /// by user id, so reusing this id shows the returning-player preselect.
    static let defaultCheckoutPayload = """
    {
      "user": {
        "id": "7849fbc5-87fd-446d-8d9c-de25298f1092",
        "validatedEmail": "test@stash.gg",
        "displayName": "Test User"
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
      "regionCode": "US"
    }
    """
}
