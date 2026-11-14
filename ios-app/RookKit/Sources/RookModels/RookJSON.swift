import Foundation

/// JSON coders configured for the backend API.
///
/// Timestamps are produced by JavaScript `Date.toISOString()` ("2026-03-14T18:02:11.123Z"), but older
/// items may lack fractional seconds, so decoding accepts both. Encoding always emits fractional seconds
/// to match what the web app writes. Calendar-day fields (e.g. `lastPerformedDate: "2026-03-14"`) are
/// modelled as `String` day keys, not `Date`, so they are never shifted by time zones.
public enum RookJSON {
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = ISO8601.parse(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognized date: \(string)"
                )
            }
            return date
        }
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601.format(date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

/// Thread-safe ISO 8601 helpers (formatters are created per call; they are cheap relative to network I/O).
public enum ISO8601 {
    public static func parse(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    public static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
