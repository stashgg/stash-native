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
