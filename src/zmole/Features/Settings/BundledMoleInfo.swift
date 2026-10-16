import Foundation

/// Reads the bundled mole identity from `Contents/Resources/mole`, never from a
/// system-installed `mo`.
enum BundledMoleInfo {
    static func sourceVersionURL(in bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?.appendingPathComponent("mole/SOURCE_VERSION")
    }

    static func executableURL(in bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?.appendingPathComponent("mole/mole")
    }

    /// The pinned upstream tag from `SOURCE_VERSION` (e.g. `V1.55.0`), or nil.
    static func tag(in bundle: Bundle = .main) -> String? {
        guard let url = sourceVersionURL(in: bundle),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return parseTag(contents)
    }

    static func parseTag(_ contents: String) -> String? {
        for line in contents.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("upstream_tag=") {
                let value = String(trimmed.dropFirst("upstream_tag=".count))
                    .trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}
