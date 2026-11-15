import Foundation

/// Finds cooking times inside method steps ("simmer for 20-25 minutes", "bake 1 hr 15 mins")
/// so each one can become a one-tap timer.
enum DurationDetector {
    struct Match: Hashable, Identifiable {
        var id: String { "\(seconds)-\(label)" }
        let seconds: Int
        let label: String
    }

    // number (optional range) + unit, optionally followed by a second "and 30 minutes" part.
    private static let unit = "(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\\b"
    private static let number = "(\\d+(?:[.,]\\d+)?|½|an?|one|two|three|four|five|six|ten|fifteen|twenty|thirty|forty|forty-five)"
    private static let regex = try! NSRegularExpression(
        pattern: "\\b\(number)(?:\\s*(?:-|–|to)\\s*(\\d+(?:[.,]\\d+)?))?\\s*\(unit)(?:\\s*(?:and\\s*)?(\\d+)\\s*(minutes?|mins?|m)\\b)?",
        options: .caseInsensitive)

    private static let words: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "ten": 10,
        "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40, "forty-five": 45, "½": 0.5,
    ]

    static func matches(in text: String) -> [Match] {
        let ns = text as NSString
        var out: [Match] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let numStr = ns.substring(with: m.range(at: 1)).lowercased()
            let unitStr = ns.substring(with: m.range(at: 3)).lowercased()
            guard var value = Double(numStr.replacingOccurrences(of: ",", with: ".")) ?? words[numStr] else { continue }
            var prefix = ""
            // "half an hour"
            if numStr == "an" || numStr == "a",
               m.range.location >= 5, ns.substring(with: NSRange(location: m.range.location - 5, length: 5)).lowercased() == "half " {
                value = 0.5
                prefix = "half "
            }
            // Bare "m"/"s"/"h" only count when attached to a digit ("20m"), to avoid false hits.
            if unitStr.count == 1, Double(numStr) == nil { continue }

            var seconds: Double
            switch unitStr.first {
            case "h": seconds = value * 3600
            case "m": seconds = value * 60
            default: seconds = value
            }
            if m.range(at: 4).location != NSNotFound, let extra = Double(ns.substring(with: m.range(at: 4))) {
                seconds += extra * 60
            }
            let s = Int(seconds.rounded())
            guard s >= 10, s <= 24 * 3600 else { continue }
            let label = prefix + ns.substring(with: m.range).trimmingCharacters(in: .whitespaces)
            if !out.contains(where: { $0.seconds == s }) { out.append(Match(seconds: s, label: label)) }
        }
        return out
    }

    static func totalMinutes(in text: String) -> Int? {
        guard let first = matches(in: text).first else { return nil }
        return max(1, first.seconds / 60)
    }
}
