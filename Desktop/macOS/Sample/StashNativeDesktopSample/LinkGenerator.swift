//
//  LinkGenerator.swift
//  StashNativeDesktopSample
//
//  Calls the Stash server endpoint that mints a quick-pay checkout link.
//

import Foundation

struct SampleError: Error {
    let message: String
}

enum LinkGenerator {

    /// POSTs the payload verbatim, signed with the HMAC helper, and returns the generated URL.
    static func generateCheckoutUrl(environment: StashEnvironment,
                                    appId: String,
                                    ingressSecret: String,
                                    payload: String,
                                    completion: @escaping (Result<String, SampleError>) -> Void) {
        guard let url = URL(string: environment.apiBaseUrl + "/sdk/server/checkout_links/generate_quick_pay_url") else {
            completion(.failure(SampleError(message: "Bad endpoint URL")))
            return
        }
        // Sign the exact bytes that go on the wire, then send them unchanged.
        let bodyData = Data(payload.utf8)
        guard let signature = StashHmac.signature(appId: appId, ingressSecretB64: ingressSecret, body: bodyData) else {
            completion(.failure(SampleError(message: "Ingress secret is not valid base64")))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(signature, forHTTPHeaderField: "x-stash-hmac-signature")
        request.httpBody = bodyData

        URLSession.shared.dataTask(with: request) { data, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let result: Result<String, SampleError>
            if let error = error {
                result = .failure(SampleError(message: "Request failed: \(error.localizedDescription)"))
            } else if !(200..<300).contains(statusCode) {
                result = .failure(SampleError(message: "Server returned HTTP \(statusCode)"))
            } else if let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let generated = json["url"] as? String, !generated.isEmpty {
                result = .success(generated)
            } else {
                result = .failure(SampleError(message: "Response had no url field"))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}
