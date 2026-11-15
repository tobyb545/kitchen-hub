import Foundation

/// Best-effort parser for recipe text pasted or sent without a URL — a WhatsApp message,
/// notes copied from somewhere, and text read from photos and screenshots.
enum TextRecipeParser {
    private static let ingredientHeader = try! NSRegularExpression(
        pattern: "^(ingredients?|what you('| wi)?ll need|you will need|shopping list|for the [a-z ]+)\\s*:?$",
        options: .caseInsensitive)
    private static let methodHeader = try! NSRegularExpression(
        pattern: "^(method|instructions?|directions?|steps?|preparation|how to make( it)?|to make)\\s*:?$",
        options: .caseInsensitive)
    private static let servesLine = try! NSRegularExpression(
        pattern: "\\b(serves|servings|makes|yield|portions)\\s*:?\\s*(\\d+)", options: .caseInsensitive)
    private static let prepLine = try! NSRegularExpression(pattern: "^prep(aration)?( time)?\\s*:", options: .caseInsensitive)
    private static let cookLine = try! NSRegularExpression(pattern: "^cook(ing)?( time)?\\s*:", options: .caseInsensitive)
    private static let numberedStep = try! NSRegularExpression(
        pattern: "^([-•*·–]\\s*|(step\\s*)?\\d{1,2}\\s*[.):\\-–]\\s|step\\s*\\d{1,2}\\b)", options: .caseInsensitive)
    private static let quantityStart = try! NSRegularExpression(
        pattern: "^([\\d½¼¾⅓⅔⅛]|a (pinch|handful|few|little|splash|knob|bunch)|pinch|handful|some |salt|pepper|\\d)",
        options: .caseInsensitive)

    static func parse(_ text: String, sourceURL: String? = nil) -> ParsedRecipe {
        let lines = text.components(separatedBy: .newlines)
            .map { fixCommonMisreads($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }

        var title = lines.first.map(stripBullet) ?? "Untitled recipe"
        title = title.replacingOccurrences(of: "^(recipe)\\s*:\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        var p = ParsedRecipe(title: title)
        p.sourceURL = sourceURL

        enum Mode { case intro, ingredients, steps }
        var mode = Mode.intro
        var sawHeaders = false
        var section: String?
        var intro: [String] = []
        var methodIsNumbered = false

        for line in lines.dropFirst() {
            // "Serves 4" on its own line, or inside the intro ("A classic bake. Serves 10.").
            // Not in the method, where "makes 12" describes something else.
            if mode != .steps, let n = servings(in: line) {
                p.servings = p.servings ?? n
                if line.count < 25 { continue }
            }
            if matches(prepLine, line) { p.prepMinutes = DurationDetector.totalMinutes(in: line); continue }
            if matches(cookLine, line) { p.cookMinutes = DurationDetector.totalMinutes(in: line); continue }

            if matches(ingredientHeader, line) {
                sawHeaders = true
                // "For the sauce:" headers become sections; a plain "Ingredients" resets them.
                section = line.lowercased().hasPrefix("for the") ? line.trimmingCharacters(in: CharacterSet(charactersIn: ":")) : nil
                if mode != .steps { mode = .ingredients }
                continue
            }
            if matches(methodHeader, line) { sawHeaders = true; mode = .steps; section = nil; continue }

            // A short line ending in ":" inside a list is a sub-section heading.
            if mode != .intro, line.hasSuffix(":"), line.count < 50 {
                section = String(line.dropLast())
                continue
            }

            switch mode {
            case .intro:
                if !sawHeaders, looksLikeIngredient(line) {
                    mode = .ingredients
                    p.ingredients.append(RecipeLine(section: section, text: stripBullet(line)))
                } else {
                    intro.append(line)
                }
            case .ingredients:
                // Without headings, a short line with no full stop ("Oil for frying", "Salt and
                // pepper") is still an ingredient; method steps are sentences.
                let shortItem = line.count <= 40 && !line.hasSuffix(".") && !matches(numberedSentence, line)
                if !sawHeaders, !looksLikeIngredient(line), !shortItem {
                    mode = .steps
                    p.steps.append(RecipeLine(section: section, text: stripStepPrefix(line)))
                } else {
                    p.ingredients.append(RecipeLine(section: section, text: stripBullet(line)))
                }
            case .steps:
                let t = stripStepPrefix(line)
                guard !t.isEmpty else { continue }
                let startsNewStep = matches(numberedStep, line)
                if startsNewStep { methodIsNumbered = true }
                // Text from photos/PDFs wraps long steps onto several lines. Join a line onto the
                // previous step when the method is numbered and this line isn't, or when the
                // previous step stopped mid-sentence.
                if !startsNewStep, let last = p.steps.last, last.section == section,
                   methodIsNumbered || !(last.text.last.map { ".!?)".contains($0) } ?? true) {
                    p.steps[p.steps.count - 1].text += " " + t
                } else {
                    p.steps.append(RecipeLine(section: section, text: t))
                }
            }
        }
        p.summary = intro.joined(separator: " ")
        return p
    }

    /// "1. Toss the…", "2) Fry…", "Step 3 Bake…" — a numbered method step, not a quantity.
    private static let numberedSentence = try! NSRegularExpression(
        pattern: "^(step\\s*\\d{1,2}\\b|\\d{1,2}\\s*[.)]\\s+[A-Za-z])", options: .caseInsensitive)

    private static func looksLikeIngredient(_ line: String) -> Bool {
        if matches(numberedSentence, line) { return false }
        let t = stripBullet(line)
        guard t.count <= 80 else { return false }
        let hasBullet = line.first.map { "-•*·–".contains($0) } ?? false
        return hasBullet || matches(quantityStart, t)
    }

    /// Text recognition on photos sometimes misreads units ("tosp" for "tbsp").
    private static func fixCommonMisreads(_ line: String) -> String {
        line.replacingOccurrences(of: "(?<=\\d|\\s|^)(tosp|tbs p|tblsp|tbps)\\b", with: "tbsp", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "(?<=\\d|\\s|^)(isp|tsp\\.)(?=\\s)", with: "tsp", options: .regularExpression)
    }

    static func stripBullet(_ s: String) -> String {
        s.replacingOccurrences(of: "^[-•*·–▢☐□]+\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Removes "1.", "1)", "Step 1:", "STEP 1 -" and bullets from the start of a method line.
    static func stripStepPrefix(_ s: String) -> String {
        stripBullet(s)
            .replacingOccurrences(of: "^(step\\s*)?\\d{1,2}\\s*[.):\\-–]\\s*", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "^step\\s*\\d{1,2}\\s*", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    private static func matches(_ r: NSRegularExpression, _ s: String) -> Bool {
        r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func servings(in s: String) -> Int? {
        guard let m = servesLine.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: 2), in: s) else { return nil }
        return Int(s[r])
    }

    private static func firstInteger(_ s: String) -> Int? {
        guard let r = s.range(of: "\\d+", options: .regularExpression) else { return nil }
        return Int(s[r])
    }
}
