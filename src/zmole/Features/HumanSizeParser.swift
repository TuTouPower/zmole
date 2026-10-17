import Foundation

/// Parses human-readable size text emitted by mole and related surfaces
/// (e.g. "2.40GB", "512 MB", "123KB", "2.5 MiB", "unknown"). Decimal units
/// follow mole's base-10 `bytes_to_human`; binary units (KiB/MiB/…) are
/// accepted for surfaces that report them.
enum HumanSizeParser {
    static func bytes(from rawValue: String?) -> Int64? {
        guard let rawValue else { return nil }
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !value.isEmpty else { return nil }
        switch value.lowercased() {
        case "0", "unknown", "n/a", "na", "--", "n/a (steam-managed)":
            return nil
        default:
            break
        }

        let characters = Array(value)
        var split = 0
        while split < characters.count,
              characters[split].isNumber || characters[split] == "." {
            split += 1
        }
        let numberText = String(characters[..<split])
        guard split > 0,
              numberText.filter({ $0 == "." }).count <= 1,
              numberText != ".",
              let number = Decimal(string: numberText, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }

        let unit = String(characters[split...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let multiplier: Decimal
        switch unit {
        case "", "B", "BYTES": multiplier = 1
        case "K", "KB": multiplier = 1_000
        case "M", "MB": multiplier = 1_000_000
        case "G", "GB": multiplier = 1_000_000_000
        case "T", "TB": multiplier = 1_000_000_000_000
        case "KIB": multiplier = 1_024
        case "MIB": multiplier = 1_048_576
        case "GIB": multiplier = 1_073_741_824
        case "TIB": multiplier = 1_099_511_627_776
        default: return nil
        }

        let bytes = NSDecimalNumber(decimal: number * multiplier)
        let maximum = NSDecimalNumber(value: Int64.max)
        guard bytes.compare(maximum) != .orderedDescending,
              bytes.compare(NSDecimalNumber(value: 0)) == .orderedDescending else { return nil }
        return bytes.int64Value
    }
}
