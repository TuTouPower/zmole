import Foundation

struct OptimizePreviewSnapshot: Equatable, Sendable {
    let generation: UUID
    let output: String
}

enum OptimizeViewModelError: Error, Equatable, Sendable {
    case missingMole

    var errorKey: String {
        switch self {
        case .missingMole:
            return "optimize.error.missing_mole"
        }
    }
}

enum OptimizeOutput {
    static func summary(stdout: String, stderr: String = "") -> String {
        [stdout, stderr]
            .map(stripANSI)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func stripANSI(_ text: String) -> String {
        var output = ""
        var iterator = text.makeIterator()

        while let character = iterator.next() {
            guard character == "\u{001B}" else {
                output.append(character)
                continue
            }

            guard iterator.next() == "[" else { continue }
            while let control = iterator.next() {
                guard let scalar = control.unicodeScalars.first else { continue }
                if (0x40...0x7E).contains(scalar.value) { break }
            }
        }

        return output
    }
}
