import Foundation

/// Converts recipe text between US measures (cups, oz, °F) and metric (grams, ml, °C) for display.
/// The saved recipe is never changed: conversion is applied on the fly, after serving scaling.
enum UnitConverter {
    enum Measures: String, CaseIterable, Identifiable {
        case original, cups, grams
        var id: String { rawValue }
        var label: String {
            switch self {
            case .original: return "As written"
            case .cups: return "Cups"
            case .grams: return "Grams"
            }
        }
    }

    enum Temperature: String, CaseIterable, Identifiable {
        case original, fahrenheit, celsius
        var id: String { rawValue }
        var label: String {
            switch self {
            case .original: return "As written"
            case .fahrenheit: return "°F"
            case .celsius: return "°C"
            }
        }
    }

    /// Ingredient line: converts the leading quantity, then any temperatures.
    static func convertIngredient(_ line: String, measures: Measures, temperature: Temperature) -> String {
        convertTemperatures(in: convertMeasure(line, to: measures), to: temperature)
    }

    // MARK: - Measures

    private enum Unit {
        case cup, tbsp, tsp, flOz, pint, stick, ml, litre, gram, kg, oz, lb

        var isUS: Bool { [.cup, .flOz, .pint, .stick, .oz, .lb].contains(self) }
        var isMetric: Bool { [.ml, .litre, .gram, .kg].contains(self) }
        var isSpoon: Bool { self == .tbsp || self == .tsp }

        /// Millilitres per unit, for volume units.
        var ml: Double? {
            switch self {
            case .cup: return 236.588
            case .tbsp: return 14.787
            case .tsp: return 4.929
            case .flOz: return 29.574
            case .pint: return 473.176
            case .ml: return 1
            case .litre: return 1000
            default: return nil
            }
        }

        /// Grams per unit, for weight units.
        var grams: Double? {
            switch self {
            case .gram: return 1
            case .kg: return 1000
            case .oz: return 28.3495
            case .lb: return 453.592
            case .stick: return 113.4   // US stick of butter
            default: return nil
            }
        }
    }

    /// Unit words, longest first so "fl oz" wins over "oz" and "tbsp" over "t".
    private static let unitWords: [(String, Unit)] = [
        ("tablespoons", .tbsp), ("tablespoon", .tbsp), ("tbsps", .tbsp), ("tbsp", .tbsp), ("tbs", .tbsp),
        ("teaspoons", .tsp), ("teaspoon", .tsp), ("tsps", .tsp), ("tsp", .tsp),
        ("fluid ounces", .flOz), ("fluid ounce", .flOz), ("fl. oz", .flOz), ("fl oz", .flOz),
        ("millilitres", .ml), ("milliliters", .ml), ("millilitre", .ml), ("milliliter", .ml), ("ml", .ml),
        ("litres", .litre), ("liters", .litre), ("litre", .litre), ("liter", .litre), ("l", .litre),
        ("kilograms", .kg), ("kilogram", .kg), ("kg", .kg),
        ("grams", .gram), ("gram", .gram), ("gr", .gram), ("g", .gram),
        ("ounces", .oz), ("ounce", .oz), ("oz", .oz),
        ("pounds", .lb), ("pound", .lb), ("lbs", .lb), ("lb", .lb),
        ("cups", .cup), ("cup", .cup), ("c", .cup),
        ("pints", .pint), ("pint", .pint),
        ("sticks", .stick), ("stick", .stick),
    ]

    private static let amount = "(\\d+\\s+\\d+/\\d+|\\d+\\s*[½¼¾⅓⅔⅛⅜⅝⅞]|\\d+/\\d+|\\d+(?:[.,]\\d+)?|[½¼¾⅓⅔⅛⅜⅝⅞])"
    private static let unitPattern = unitWords.map { NSRegularExpression.escapedPattern(for: $0.0) }.joined(separator: "|")
    /// "1 ½ cups", "200g", "2-3 tbsp", "1 cup (125g)". Groups: 1 amount, 2 range end, 3 unit, 4 parenthetical.
    private static let quantity = try! NSRegularExpression(
        pattern: "^\\s*\(amount)(?:\\s*(?:-|–|to)\\s*\(amount))?\\s*(\(unitPattern))\\.?(?![a-z])(\\s*\\([^)]*\\))?",
        options: .caseInsensitive)

    private static func unit(for word: String) -> Unit? {
        let w = word.lowercased()
        return unitWords.first { $0.0 == w }?.1
    }

    static func convertMeasure(_ line: String, to target: Measures) -> String {
        guard target != .original else { return line }
        let ns = line as NSString
        guard let m = quantity.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              let a = IngredientScaler.parse(ns.substring(with: m.range(at: 1))),
              let unit = unit(for: ns.substring(with: m.range(at: 3))) else { return line }
        let b = m.range(at: 2).location != NSNotFound ? IngredientScaler.parse(ns.substring(with: m.range(at: 2))) : nil
        let rest = ns.substring(from: m.range.location + m.range.length)
        let ingredient = rest.lowercased()

        // "1 cup (125g) flour": the recipe already gives the other measure, so use it as written.
        let paren = m.range(at: 4).location != NSNotFound ? ns.substring(with: m.range(at: 4)) : ""
        let inner = String(paren.trimmingCharacters(in: .whitespaces).dropFirst().dropLast())
        let innerMatch = quantity.firstMatch(in: inner, range: NSRange(location: 0, length: (inner as NSString).length))
        if let im = innerMatch, let innerUnit = self.unit(for: (inner as NSString).substring(with: im.range(at: 3))),
           (target == .grams && innerUnit.isMetric) || (target == .cups && innerUnit.isUS) {
            return inner.trimmingCharacters(in: .whitespaces) + rest
        }

        let wantsMetric = target == .grams
        // Already in the target system, or spoons (used everywhere): leave as written.
        if unit.isSpoon || (wantsMetric && unit.isMetric) || (!wantsMetric && unit.isUS) { return line }

        let convert: (Double) -> (String, String)? = { value in
            wantsMetric ? toMetric(value, unit, ingredient) : toUS(value, unit, ingredient)
        }
        guard let (first, unitText) = convert(a) else { return line }
        var out = first
        if let b, let (second, _) = convert(b) { out += "–" + second }
        // Keep a parenthetical that isn't a measurement, e.g. "1 cup (packed) brown sugar".
        let keptParen = innerMatch == nil ? paren : ""
        return out + unitText + keptParen + rest
    }

    private static func toMetric(_ v: Double, _ unit: Unit, _ ingredient: String) -> (String, String)? {
        if let g = unit.grams { return grams(v * g) }
        guard let ml = unit.ml else { return nil }
        let millilitres = v * ml
        if let density = density(of: ingredient) { return grams(millilitres / 236.588 * density) }
        return millilitres >= 1000 ? (trim(millilitres / 1000, places: 2), " litres") : (String(Int(roundTo(millilitres, millilitres >= 50 ? 5 : 1))), " ml")
    }

    private static func toUS(_ v: Double, _ unit: Unit, _ ingredient: String) -> (String, String)? {
        if let ml = unit.ml { return volumeUS(v * ml) }
        guard let g = unit.grams else { return nil }
        let gramsValue = v * g
        if let density = density(of: ingredient) { return volumeUS(gramsValue / density * 236.588) }
        // Weighed ingredients with no cup equivalent (meat, veg, cheese blocks...): ounces/pounds.
        let oz = gramsValue / 28.3495
        if oz >= 16 { return (IngredientScaler.format(roundTo(oz / 16, 0.25)), " lb") }
        return (IngredientScaler.format(max(0.5, roundTo(oz, oz < 4 ? 0.5 : 1))), " oz")
    }

    private static func grams(_ g: Double) -> (String, String) {
        if g >= 1000 { return (trim(g / 1000, places: 2), " kg") }
        return (String(Int(roundTo(g, g >= 100 ? 5 : 1))), "g")
    }

    private static func volumeUS(_ ml: Double) -> (String, String) {
        let cups = ml / 236.588
        if cups >= 0.24 {
            let snapped = snapCups(cups)
            let unit = snapped > 1 ? " cups" : " cup"
            // Too far from a cup measure (e.g. 200g butter = 0.88 cup): "¾ cup + 2 tbsp".
            if abs(snapped - cups) / cups > 0.06, cups < 4 {
                let quarters: Double = floor(cups * 4) / 4
                let thirds: Double = floor(cups * 3) / 3
                let base = max(quarters, thirds)
                let tbsp = roundTo((cups - base) * 16, 1)
                if base > 0, tbsp >= 1 {
                    return (IngredientScaler.format(base), (base > 1 ? " cups" : " cup") + " + \(Int(tbsp)) tbsp")
                }
            }
            return (IngredientScaler.format(snapped), unit)
        }
        let tbsp = ml / 14.787
        if tbsp >= 1 { return (IngredientScaler.format(roundTo(tbsp, 0.5)), " tbsp") }
        return (IngredientScaler.format(max(0.25, roundTo(ml / 4.929, 0.25))), " tsp")
    }

    /// Nearest quarter or third of a cup, the measures people actually own.
    private static func snapCups(_ cups: Double) -> Double {
        let quarter = roundTo(cups, 0.25), third = (cups * 3).rounded() / 3
        return abs(quarter - cups) <= abs(third - cups) ? quarter : third
    }

    private static func roundTo(_ v: Double, _ step: Double) -> Double { (v / step).rounded() * step }
    private static func trim(_ v: Double, places: Int) -> String {
        v.formatted(.number.precision(.fractionLength(0...places)))
    }

    /// Grams per US cup. Order matters: more specific names first ("peanut butter" before "butter").
    /// nil means a liquid, which converts by volume (ml) instead of weight.
    private static let densities: [(String, Double?)] = [
        ("cooked", nil), ("peanut butter", 258), ("almond butter", 250), ("buttermilk", nil), ("butter", 227),
        ("cream cheese", 230), ("sour cream", 230), ("mascarpone", 230), ("creme fraiche", 230), ("crème fraîche", 230),
        ("coconut milk", nil), ("coconut cream", nil), ("desiccated coconut", 85), ("shredded coconut", 85),
        ("icing sugar", 120), ("powdered sugar", 120), ("confectioners", 120),
        ("brown sugar", 220), ("muscovado", 220), ("demerara", 220), ("sugar", 200),
        ("almond flour", 96), ("ground almonds", 96), ("cornflour", 128), ("cornstarch", 128), ("corn starch", 128),
        ("flour", 125), ("cocoa", 85), ("baking powder", 220), ("bicarbonate", 220), ("baking soda", 220),
        ("rolled oats", 90), ("oats", 90), ("panko", 50), ("breadcrumbs", 108), ("bread crumbs", 108),
        ("chocolate chips", 170), ("chocolate", 170), ("raisins", 150), ("sultanas", 150), ("dried fruit", 150),
        ("parmesan", 100), ("cheese", 113),
        ("walnuts", 120), ("pecans", 110), ("almonds", 140), ("nuts", 125), ("seeds", 140),
        ("yogurt", 245), ("yoghurt", 245),
        ("honey", 340), ("golden syrup", 340), ("maple syrup", 315), ("syrup", 330), ("jam", 320), ("treacle", 340),
        ("rice", 185), ("quinoa", 170), ("couscous", 175), ("lentils", 200), ("polenta", 160),
        ("salt", 290),
        ("milk", nil), ("water", nil), ("stock", nil), ("broth", nil), ("cream", nil),
        ("juice", nil), ("wine", nil), ("oil", nil), ("vinegar", nil), ("sauce", nil),
    ]

    private static func density(of ingredient: String) -> Double? {
        for (name, grams) in densities where ingredient.contains(name) { return grams }
        return nil
    }

    // MARK: - Temperatures

    /// "180°C", "180 ºC", "180C", "350°F", "350 degrees F", "180-200°C", "220 degrees Celsius".
    private static let temperature = try! NSRegularExpression(
        pattern: "\\b(\\d{2,3})(?:\\s*(?:-|–|to)\\s*(\\d{2,3}))?(?:\\s*[°º]\\s*|\\s*degrees?\\s+|\\s*deg\\.?\\s+|\\s*)(?:([CF])(?![a-zA-Z])|(?i:(celsius|centigrade|fahrenheit)))")

    static func convertTemperatures(in text: String, to target: Temperature) -> String {
        guard target != .original else { return text }
        let ns = text as NSString
        var out = text
        for m in temperature.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let letterRange = m.range(at: 3).location != NSNotFound ? m.range(at: 3) : m.range(at: 4)
            let isCelsius = ns.substring(with: letterRange).lowercased().first == "c"
            if isCelsius == (target == .celsius) { continue }
            guard let a = Double(ns.substring(with: m.range(at: 1))) else { continue }
            var value = convert(a, celsius: isCelsius)
            if m.range(at: 2).location != NSNotFound, let b = Double(ns.substring(with: m.range(at: 2))) {
                value += "–" + convert(b, celsius: isCelsius)
            }
            out = (out as NSString).replacingCharacters(in: m.range, with: value + (isCelsius ? "°F" : "°C"))
        }
        return out
    }

    /// Oven-friendly rounding: 180°C → 350°F, 200°C → 400°F, 350°F → 180°C, 425°F → 220°C.
    private static func convert(_ v: Double, celsius: Bool) -> String {
        if celsius {
            let f = v * 9 / 5 + 32
            return String(Int(roundTo(f, f >= 250 ? 25 : 5)))
        }
        let c = (v - 32) * 5 / 9
        return String(Int(roundTo(c, c >= 100 ? 10 : 5)))
    }

    /// Whether any line mentions an oven/cooking temperature, so the °C/°F control is worth showing.
    static func containsTemperature(_ texts: [String]) -> Bool {
        texts.contains { temperature.firstMatch(in: $0, range: NSRange(location: 0, length: ($0 as NSString).length)) != nil }
    }
}
