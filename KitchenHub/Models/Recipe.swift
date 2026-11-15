import Foundation
import SwiftData

/// One line in a recipe's ingredient list or method, optionally inside a named section
/// ("For the sauce", "To serve"...).
struct RecipeLine: Codable, Hashable, Identifiable {
    var id = UUID()
    var section: String?
    var text: String
}

/// A recipe as produced by any of the parsers, before it is saved.
struct ParsedRecipe {
    var title: String
    var summary: String = ""
    var sourceURL: String?
    var imageURL: String?
    var servings: Int?
    var yieldText: String?
    var prepMinutes: Int?
    var cookMinutes: Int?
    var totalMinutes: Int?
    var ingredients: [RecipeLine] = []
    var steps: [RecipeLine] = []

    var looksValid: Bool { !ingredients.isEmpty && !steps.isEmpty }
}

@Model
final class Recipe {
    var id: UUID = UUID()
    var title: String = ""
    var summary: String = ""
    var sourceURL: String?
    var imageURL: String?
    var servings: Int?
    var yieldText: String?
    var prepMinutes: Int?
    var cookMinutes: Int?
    var totalMinutes: Int?
    // Stored as JSON so SwiftData never has to reason about nested Codable arrays.
    var ingredientsData: Data = Data()
    var stepsData: Data = Data()
    var notes: String = ""
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var lastCookedAt: Date?

    init(parsed: ParsedRecipe) {
        id = UUID()
        title = parsed.title
        summary = parsed.summary
        sourceURL = parsed.sourceURL
        imageURL = parsed.imageURL
        servings = parsed.servings
        yieldText = parsed.yieldText
        prepMinutes = parsed.prepMinutes
        cookMinutes = parsed.cookMinutes
        totalMinutes = parsed.totalMinutes ?? Recipe.sum(parsed.prepMinutes, parsed.cookMinutes)
        createdAt = Date()
        ingredients = parsed.ingredients
        steps = parsed.steps
    }

    var ingredients: [RecipeLine] {
        get { (try? JSONDecoder().decode([RecipeLine].self, from: ingredientsData)) ?? [] }
        set { ingredientsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var steps: [RecipeLine] {
        get { (try? JSONDecoder().decode([RecipeLine].self, from: stepsData)) ?? [] }
        set { stepsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var displayTotalMinutes: Int? { totalMinutes ?? Recipe.sum(prepMinutes, cookMinutes) }

    var sourceHost: String? {
        guard let s = sourceURL, let host = URL(string: s)?.host else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private static func sum(_ a: Int?, _ b: Int?) -> Int? {
        switch (a, b) {
        case (nil, nil): return nil
        default: return (a ?? 0) + (b ?? 0)
        }
    }
}

extension Int {
    /// 95 -> "1 hr 35 min"
    var minutesText: String {
        let h = self / 60, m = self % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h) hr" }
        return "\(h) hr \(m) min"
    }
}
