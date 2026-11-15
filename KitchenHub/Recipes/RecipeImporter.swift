import Foundation

/// Turns whatever was sent (a link, or pasted text) into a ParsedRecipe.
///
/// Order of attempts for a link: the page's schema.org JSON-LD (fast, exact) → the same after
/// rendering the page in WebKit → the text parser on the page's visible text. Pasted text goes
/// straight to the text parser.
enum RecipeImporter {
    enum ImportError: LocalizedError {
        case empty, fetchFailed(String), noRecipeFound
        var errorDescription: String? {
            switch self {
            case .empty: return "Nothing to import — send a link or some recipe text."
            case .fetchFailed(let why): return "Couldn't open that page (\(why))."
            case .noRecipeFound:
                return "Couldn't find a recipe there. Try copying the recipe text and pasting it instead, or take a screenshot and add that."
            }
        }
    }

    static func importRecipe(from input: String) async throws -> ParsedRecipe {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.empty }
        if let url = extractURL(from: trimmed), trimmed.count < url.absoluteString.count + 200 {
            // Mostly a link (perhaps "Check this out: https://...").
            return try await importURL(url)
        }
        return try await importText(trimmed, sourceURL: nil)
    }

    static func importURL(_ url: URL) async throws -> ParsedRecipe {
        // 1. Quick fetch.
        var html = ""
        var fetchError: Error?
        do { html = try await fetch(url) } catch { fetchError = error }
        if let parsed = JSONLDRecipeParser.parse(html: html, sourceURL: url) { return parsed }

        // 2. Real browser engine, for sites behind a bot check or that build the page in JS.
        if let rendered = await WebPageLoader.html(for: url), !rendered.isEmpty {
            if let parsed = JSONLDRecipeParser.parse(html: rendered, sourceURL: url) { return parsed }
            html = rendered
        }
        if html.isEmpty, let fetchError { throw fetchError }

        // 3. Format the visible page text.
        let text = HTMLText.pageText(html)
        var parsed = try await importText(text, sourceURL: url.absoluteString)
        if parsed.imageURL == nil { parsed.imageURL = HTMLText.meta("og:image", in: html) }
        if let pageTitle = HTMLText.title(in: html) { parsed.title = pageTitle }
        return parsed
    }

    static func importText(_ text: String, sourceURL: String?) async throws -> ParsedRecipe {
        let parsed = TextRecipeParser.parse(text, sourceURL: sourceURL)
        guard parsed.looksValid else { throw ImportError.noRecipeFound }
        return parsed
    }

    static func extractURL(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        guard let url = match?.url, url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }

    private static func fetch(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        // Many recipe sites serve a stripped or blocked page to unknown clients.
        request.setValue("Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("en-GB,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ImportError.fetchFailed("HTTP \(http.statusCode)")
            }
            return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        } catch let e as ImportError {
            throw e
        } catch {
            throw ImportError.fetchFailed(error.localizedDescription)
        }
    }
}
