//
//  EventLog.swift
//  StashNativeDesktopSample
//
//  Every event from the C ABI callback, in order. The window shows them and the proof runner
//  judges them. Registered once at launch; the facade delegate is set separately by the window.
//

import Foundation
import StashNativeDesktop

final class EventLog {
    static let shared = EventLog()

    struct Entry {
        let type: String
        let payload: String

        /// What the window shows and the proof runner prints. Payloads can carry the checkout URL
        /// (navigation) or order data (paymentSuccess), so only fields that are safe to display
        /// are rendered; everything else is reported by size.
        var summary: String {
            switch type {
            case "pageLoaded", "webProcessCrashed":
                return "\(type) \(payload)"
            case "navigation":
                return "\(type) \(Entry.origin(of: payload))"
            case "navigationBlocked":
                return "\(type) \(Entry.field("reason", in: payload))"
            default:
                return payload.isEmpty ? type : "\(type) (\(payload.utf8.count) bytes)"
            }
        }

        /// scheme://host[:port], matching url::origin in the shared contract.
        static func origin(of url: String) -> String {
            guard let parsed = URL(string: url), let scheme = parsed.scheme else { return "" }
            let port = parsed.port.map { ":\($0)" } ?? ""
            return "\(scheme)://\(parsed.host ?? "")\(port)"
        }

        private static func field(_ name: String, in json: String) -> String {
            guard let range = json.range(of: "\"\(name)\":\"") else { return "" }
            let rest = json[range.upperBound...]
            return String(rest.prefix { $0 != "\"" })
        }
    }

    private(set) var entries: [Entry] = []
    var onEvent: ((Entry) -> Void)?

    private init() {}

    func install() {
        StashNativeDesktop_SetEventCallback({ type, payload, _ in
            let entry = Entry(type: type.map { String(cString: $0) } ?? "",
                              payload: payload.map { String(cString: $0) } ?? "")
            EventLog.shared.record(entry)
        }, nil)
    }

    private func record(_ entry: Entry) {
        entries.append(entry)
        onEvent?(entry)
    }

    func clear() {
        entries.removeAll()
    }

    var types: [String] {
        entries.map { $0.type }
    }
}
