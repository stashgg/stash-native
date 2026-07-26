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
        guard let secret = Data(base64Encoded: ingressSecretB64) else { return nil }
        let unixMillis = String(Int64(Date().timeIntervalSince1970 * 1000))
        var message = Data("\(unixMillis).".utf8)
        message.append(body)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret))
        return "v1;\(appId);\(unixMillis);\(Data(mac).base64EncodedString())"
    }
}
