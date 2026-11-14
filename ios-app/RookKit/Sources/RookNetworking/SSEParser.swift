import Foundation

/// One Server-Sent Event.
public struct SSEEvent: Equatable, Sendable {
    public var event: String
    public var data: String

    public init(event: String, data: String) {
        self.event = event
        self.data = data
    }
}

/// Incremental Server-Sent Events parser (WHATWG event-stream format).
///
/// Feed arbitrary text chunks as they arrive; complete events are returned once their terminating blank
/// line is seen. Handles `\n`, `\r\n` and `\r` line endings, multi-line `data:` fields, comments (`:`),
/// and an optional single space after the colon. Events without data are ignored, per the spec.
public struct SSEParser: Sendable {
    /// Scalars of the line currently being read (scanned per scalar, because Swift treats "\r\n" as a
    /// single Character, which would make Character-based splitting ambiguous across chunks).
    private var line = String.UnicodeScalarView()
    /// True when the previous chunk ended with "\r", so a leading "\n" in the next chunk is part of it.
    private var lastWasCR = false
    private var eventName = ""
    private var dataLines: [String] = []

    public init() {}

    public mutating func feed(_ chunk: String) -> [SSEEvent] {
        var events: [SSEEvent] = []
        for scalar in chunk.unicodeScalars {
            switch scalar {
            case "\n" where lastWasCR:
                lastWasCR = false // second half of "\r\n"; the line was already processed at "\r"
            case "\n", "\r":
                lastWasCR = scalar == "\r"
                let completed = String(line)
                line.removeAll()
                if let event = process(line: completed) { events.append(event) }
            default:
                lastWasCR = false
                line.append(scalar)
            }
        }
        return events
    }

    /// Call when the stream ends: dispatches a final event that lacked its trailing blank line.
    public mutating func finish() -> [SSEEvent] {
        var events: [SSEEvent] = []
        if !line.isEmpty {
            let completed = String(line)
            line.removeAll()
            if let event = process(line: completed) { events.append(event) }
        }
        if let event = dispatch() { events.append(event) }
        return events
    }

    private mutating func process(line: String) -> SSEEvent? {
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }
        switch field {
        case "event": eventName = String(value)
        case "data": dataLines.append(String(value))
        default: break // id / retry / unknown fields are not used by the backend
        }
        return nil
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            eventName = ""
            dataLines = []
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(event: eventName.isEmpty ? "message" : eventName, data: dataLines.joined(separator: "\n"))
    }
}
