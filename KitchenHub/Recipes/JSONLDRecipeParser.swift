import Foundation

/// Extracts a schema.org `Recipe` from a page's `<script type="application/ld+json">` blocks.
/// Nearly every major recipe site (BBC Good Food, AllRecipes, NYT, Serious Eats, blogs on
/// WordPress recipe plugins...) publishes this for Google, so it's the most reliable source.
enum JSONLDRecipeParser {
    static func parse(html: String, sourceURL: URL?) -> ParsedRecipe? {
        guard let regex = try? NSRegularExpression(
            pattern: "<script[^>]*type=[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for match in matches {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let raw = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = raw.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let recipe = findRecipe(in: json) else { continue }
            if let parsed = build(from: recipe, sourceURL: sourceURL, html: html), parsed.looksValid {
                return parsed
            }
        }
        return nil
    }

    // MARK: - Locating the Recipe node

    private static func isRecipe(_ dict: [String: Any]) -> Bool {
        if let t = dict["@type"] as? String { return t.caseInsensitiveCompare("Recipe") == .orderedSame }
        if let ts = dict["@type"] as? [String] { return ts.contains { $0.caseInsensitiveCompare("Recipe") == .orderedSame } }
        return false
    }

    private static func findRecipe(in node: Any, depth: Int = 0) -> [String: Any]? {
        guard depth < 8 else { return nil }
        if let dict = node as? [String: Any] {
            if isRecipe(dict) { return dict }
            for key in ["@graph", "mainEntity", "mainEntityOfPage", "itemListElement", "item"] {
                if let child = dict[key], let found = findRecipe(in: child, depth: depth + 1) { return found }
            }
        } else if let array = node as? [Any] {
            for child in array {
                if let found = findRecipe(in: child, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    // MARK: - Building

    private static func build(from r: [String: Any], sourceURL: URL?, html: String) -> ParsedRecipe? {
        guard let name = text(r["name"]) ?? HTMLText.title(in: html) else { return nil }
        var p = ParsedRecipe(title: HTMLText.plain(name))
        p.summary = text(r["description"]).map(HTMLText.plain) ?? ""
        p.sourceURL = sourceURL?.absoluteString
        p.imageURL = image(r["image"]) ?? HTMLText.meta("og:image", in: html)
        p.prepMinutes = ISODuration.minutes(text(r["prepTime"]))
        p.cookMinutes = ISODuration.minutes(text(r["cookTime"]))
        p.totalMinutes = ISODuration.minutes(text(r["totalTime"]))

        let yields = yieldStrings(r["recipeYield"])
        p.yieldText = yields.first { $0.rangeOfCharacter(from: .letters) != nil } ?? yields.first
        p.servings = yields.lazy.compactMap(firstInteger).first

        let rawIngredients = (r["recipeIngredient"] ?? r["ingredients"]).map(stringArray) ?? []
        p.ingredients = rawIngredients.map(HTMLText.plain).filter { !$0.isEmpty }.map { RecipeLine(text: $0) }

        var steps: [RecipeLine] = []
        collectSteps(r["recipeInstructions"], section: nil, into: &steps)
        p.steps = steps
        return p
    }

    private static func collectSteps(_ node: Any?, section: String?, into steps: inout [RecipeLine]) {
        switch node {
        case let s as String:
            // A single blob: split on line breaks / paragraph tags.
            let normalised = s.replacingOccurrences(of: "<(br|/p|/li)\\b[^>]*>", with: "\n",
                                                    options: [.regularExpression, .caseInsensitive])
            for part in normalised.components(separatedBy: .newlines) {
                let t = TextRecipeParser.stripStepPrefix(HTMLText.plain(part))
                if !t.isEmpty { steps.append(RecipeLine(section: section, text: t)) }
            }
        case let array as [Any]:
            for child in array { collectSteps(child, section: section, into: &steps) }
        case let dict as [String: Any]:
            let type = (dict["@type"] as? String) ?? ((dict["@type"] as? [String])?.first ?? "")
            if type == "HowToSection" || dict["itemListElement"] != nil {
                let name = text(dict["name"]).map(HTMLText.plain)
                collectSteps(dict["itemListElement"], section: name ?? section, into: &steps)
            } else if let t = text(dict["text"]) ?? text(dict["name"]) ?? text(dict["description"]) {
                let clean = TextRecipeParser.stripStepPrefix(HTMLText.plain(t))
                if !clean.isEmpty { steps.append(RecipeLine(section: section, text: clean)) }
            }
        default:
            break
        }
    }

    // MARK: - Value helpers

    private static func text(_ v: Any?) -> String? {
        switch v {
        case let s as String: return s.isEmpty ? nil : s
        case let n as NSNumber: return n.stringValue
        case let a as [Any]: return a.lazy.compactMap { text($0) }.first
        case let d as [String: Any]: return text(d["@value"] ?? d["name"] ?? d["text"])
        default: return nil
        }
    }

    private static func stringArray(_ v: Any) -> [String] {
        if let a = v as? [Any] { return a.compactMap { text($0) } }
        if let s = text(v) { return s.components(separatedBy: .newlines) }
        return []
    }

    private static func yieldStrings(_ v: Any?) -> [String] {
        guard let v else { return [] }
        if let a = v as? [Any] { return a.compactMap { text($0) } }
        return text(v).map { [$0] } ?? []
    }

    private static func image(_ v: Any?) -> String? {
        switch v {
        case let s as String: return s
        case let a as [Any]: return a.lazy.compactMap { image($0) }.first
        case let d as [String: Any]: return (d["url"] as? String) ?? (d["contentUrl"] as? String)
        default: return nil
        }
    }

    private static func firstInteger(_ s: String) -> Int? {
        guard let r = s.range(of: "\\d+", options: .regularExpression) else { return nil }
        return Int(s[r])
    }
}

/// ISO-8601 durations as used by schema.org: "PT1H30M", "P0DT0H45M", "PT20M".
enum ISODuration {
    static func minutes(_ s: String?) -> Int? {
        guard let s = s?.uppercased(), s.hasPrefix("P") else { return nil }
        var total = 0.0, number = "", inTime = false
        for ch in s.dropFirst() {
            if ch == "T" { inTime = true; continue }
            if ch.isNumber || ch == "." { number.append(ch); continue }
            let v = Double(number) ?? 0
            number = ""
            switch ch {
            case "D": total += v * 1440
            case "H": total += v * 60
            case "M": total += inTime ? v : v * 43_200
            case "S": total += v / 60
            default: break
            }
        }
        let m = Int(total.rounded())
        return m > 0 ? m : nil
    }
}
