//
//  StashHmac.swift
//  StashNativeSample
//
//  Signs server-to-server Stash API requests.
//

import Foundation
import CryptoKit

/// Builds the `x-stash-hmac-signature` header for server-to-server Stash API calls.
///
/// Format: `v1;<appId>;<unixMillis>;<base64 HMAC-SHA256>`, where the signature covers
/// `"<unixMillis>." + body` using the base64-decoded ingress secret as the key. Stash rejects
/// requests whose timestamp is more than 5 minutes from its clock.
///
/// In a real integration this signing belongs on your backend -- the ingress secret must never
/// ship inside a client app. The sample signs in-app only so the flow can be exercised on device.
enum StashHmac {

    /// Signs the exact body bytes that will be sent. Nil if the secret isn't valid base64.
    static func signature(appId: String, ingressSecretB64: String, body: Data) -> String? {
        signature(appId: appId, ingressSecretB64: ingressSecretB64, body: body,
                  unixMillis: Int64(Date().timeIntervalSince1970 * 1000))
    }

    /// Deterministic form behind the public signer; the regression vector pins the header format.
    static func signature(appId: String, ingressSecretB64: String, body: Data, unixMillis: Int64) -> String? {
        guard let secret = secretData(ingressSecretB64) else { return nil }
        var message = Data("\(unixMillis).".utf8)
        message.append(body)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret))
        return "v1;\(appId);\(unixMillis);\(Data(mac).base64EncodedString())"
    }

    /// True when the secret decodes as base64 (after padding), the same acceptance as the Android sample.
    static func isValidIngressSecret(_ ingressSecretB64: String) -> Bool {
        secretData(ingressSecretB64) != nil
    }

    /// Decodes the secret, tolerating missing `=` padding like Android's Base64.DEFAULT.
    static func secretData(_ ingressSecretB64: String) -> Data? {
        let trimmed = ingressSecretB64.trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = trimmed.count % 4
        guard !trimmed.isEmpty, remainder != 1 else { return nil }
        let padded = remainder == 0 ? trimmed : trimmed + String(repeating: "=", count: 4 - remainder)
        return Data(base64Encoded: padded)
    }
}
