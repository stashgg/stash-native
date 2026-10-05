//
//  StashHmac.swift
//  StashNativeDesktopSample
//
//  Signs server-to-server Stash API requests.
//

import Foundation
import CryptoKit

/// Builds the `x-stash-hmac-signature` header for server-to-server Stash API calls.
///
/// Format: `v1;<appId>;<unixMillis>;<base64 HMAC-SHA256>`, where the signature covers
/// `"<unixMillis>." + body` using the ingress secret's UTF-8 bytes as the key, exactly as
/// issued by Studio. Do not base64-decode it: the server verifies with the raw secret string,
/// and Studio keys use the URL-safe alphabet, which a base64 decoder rejects. Stash rejects
/// requests whose timestamp is more than 5 minutes from its clock.
///
/// In a real integration this signing belongs on your backend -- the ingress secret must never
/// ship inside a client app. The sample signs in-app only so the flow can be exercised locally.
enum StashHmac {

    /// Signs the exact body bytes that will be sent.
    static func signature(appId: String, ingressSecret: String, body: Data) -> String {
        let unixMillis = String(Int64(Date().timeIntervalSince1970 * 1000))
        var message = Data("\(unixMillis).".utf8)
        message.append(body)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: Data(ingressSecret.utf8)))
        return "v1;\(appId);\(unixMillis);\(Data(mac).base64EncodedString())"
    }
}
