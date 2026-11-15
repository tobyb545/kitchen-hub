import Foundation

/// Splits text read from a batch of photos into separate recipes.
///
/// A new recipe starts:
///  - at an "Ingredients" heading, once the text before it already holds a recipe (a method
///    heading has been seen, or it reads as a complete recipe);
///  - at a photo boundary, when the text so far is a complete recipe and the new photo is a
///    complete recipe on its own (screenshots with no headings, e.g. social-media captions).
/// Otherwise photos are joined, so one recipe spread over several screenshots stays together.
enum RecipeSplitter {
    struct Piece {
        var text: String
        /// Index of the first photo this recipe came from.
        var firstPage: Int
    }

    private static let ingredientsHeading = try! NSRegularExpression(
        pattern: "^(ingredients?|what you('| wi)?ll need|you will need)\\s*:?$", options: .caseInsensitive)
    private static let methodHeading = try! NSRegularExpression(
        pattern: "^(method|instructions?|directions?|steps?|preparation|how to make( it)?)\\s*:?$", options: .caseInsensitive)

    private struct Chunk {
        var lines: [String] = []
        var firstPage: Int
        var sawMethod = false
        var isCompleteRecipe: Bool { !lines.isEmpty && TextRecipeParser.parse(lines.joined(separator: "\n")).looksValid }
    }

    static func split(pages: [String]) -> [Piece] {
        var chunks: [Chunk] = []
        var current = Chunk(firstPage: 0)

        for (pageIndex, page) in pages.enumerated() {
            let lines = page.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }

            if current.lines.isEmpty {
                current.firstPage = pageIndex
            } else if current.isCompleteRecipe, TextRecipeParser.parse(page).looksValid {
                chunks.append(current)
                current = Chunk(firstPage: pageIndex)
            }

            // Where this photo's lines begin within the current chunk.
            var pageStart = current.lines.count
            for line in lines {
                if matches(ingredientsHeading, line), current.sawMethod || current.isCompleteRecipe {
                    // A new recipe begins. Bring its title/intro with it.
                    let carried = takeTitleLines(from: &current.lines, earliest: pageStart, newPage: pageStart > 0)
                    chunks.append(current)
                    current = Chunk(lines: carried, firstPage: pageIndex)
                    pageStart = 0
                } else if matches(methodHeading, line) {
                    current.sawMethod = true
                }
                current.lines.append(line)
            }
        }
        chunks.append(current)

        return chunks.filter { !$0.lines.isEmpty }
            .map { Piece(text: $0.lines.joined(separator: "\n"), firstPage: $0.firstPage) }
    }

    /// Pulls the lines just above an Ingredients heading that belong to the new recipe: its title
    /// and intro, but not the tail of the previous recipe's method.
    private static func takeTitleLines(from lines: inout [String], earliest: Int, newPage: Bool) -> [String] {
        var carried: [String] = []
        // If the previous recipe ended on an earlier photo, everything title-ish on this photo
        // above the heading is the new recipe's (title + intro); otherwise just a short title.
        let limit = newPage ? 4 : 2
        let floor = newPage ? earliest : 0
        while carried.count < limit, lines.count > floor, let last = lines.last {
            let belongs = newPage ? looksLikeIntro(last) : looksLikeTitle(last)
            guard belongs else { break }
            carried.insert(lines.removeLast(), at: 0)
        }
        return carried
    }

    private static func looksLikeTitle(_ line: String) -> Bool {
        line.count < 60 && !line.hasSuffix(".") && !line.hasSuffix(":")
            && line.range(of: "^[\\d•\\-*]", options: .regularExpression) == nil
    }

    private static func looksLikeIntro(_ line: String) -> Bool {
        guard let first = line.first, first.isUppercase else { return false }
        return line.range(of: "^(step\\s*)?\\d{1,2}\\s*[.):]", options: [.regularExpression, .caseInsensitive]) == nil
    }

    private static func matches(_ r: NSRegularExpression, _ s: String) -> Bool {
        r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
}
