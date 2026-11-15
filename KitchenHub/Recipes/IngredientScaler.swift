import Foundation

/// Scales the leading quantity of an ingredient line: "1 ½ cups flour" ×2 -> "3 cups flour",
/// "200g butter" ×1.5 -> "300g butter", "2-3 cloves garlic" ×2 -> "4-6 cloves garlic".
enum IngredientScaler {
    private static let unicodeFractions: [Character: Double] = [
        "½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875,
    ]
    private static let amount = "(\\d+\\s+\\d+/\\d+|\\d+\\s*[½¼¾⅓⅔⅛⅜⅝⅞]|\\d+/\\d+|\\d+(?:[.,]\\d+)?|[½¼¾⅓⅔⅛⅜⅝⅞])"
    private static let regex = try! NSRegularExpression(
        pattern: "^\\s*\(amount)(?:\\s*(?:-|–|to)\\s*\(amount))?")

    static func scale(_ line: String, by factor: Double) -> String {
        guard abs(factor - 1) > 0.001 else { return line }
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              let a = parse(ns.substring(with: m.range(at: 1))) else { return line }
        var replacement = format(a * factor)
        if m.range(at: 2).location != NSNotFound, let b = parse(ns.substring(with: m.range(at: 2))) {
            replacement += "-" + format(b * factor)
        }
        let rest = ns.substring(from: m.range.location + m.range.length)
        return replacement + rest
    }

    static func parse(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if let v = Double(t) { return v }
        if t.count == 1, let c = t.first, let f = unicodeFractions[c] { return f }
        if let last = t.last, let f = unicodeFractions[last] {
            return (Double(t.dropLast().trimmingCharacters(in: .whitespaces)) ?? 0) + f
        }
        let parts = t.split(separator: " ")
        if parts.count == 2, let whole = Double(parts[0]), let frac = parseFraction(String(parts[1])) { return whole + frac }
        return parseFraction(t)
    }

    private static func parseFraction(_ s: String) -> Double? {
        let p = s.split(separator: "/")
        guard p.count == 2, let n = Double(p[0]), let d = Double(p[1]), d != 0 else { return nil }
        return n / d
    }

    static func format(_ v: Double) -> String {
        let whole = floor(v)
        let frac = v - whole
        let nice: [(Double, String)] = [(0, ""), (0.25, "¼"), (1.0 / 3, "⅓"), (0.5, "½"), (2.0 / 3, "⅔"), (0.75, "¾"), (1, "")]
        if v < 10, let best = nice.min(by: { abs($0.0 - frac) < abs($1.0 - frac) }), abs(best.0 - frac) < 0.04 {
            let w = Int(whole) + (best.0 == 1 ? 1 : 0)
            if best.1.isEmpty { return "\(w)" }
            return w == 0 ? best.1 : "\(w)\(best.1)"
        }
        if v >= 10 { return "\(Int(v.rounded()))" }
        return String(format: "%.1f", v).replacingOccurrences(of: ".0", with: "")
    }
}
