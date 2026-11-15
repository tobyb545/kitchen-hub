import Foundation
import UIKit
import UniformTypeIdentifiers

/// A recipe from a batch of photos/files, with the photo to show alongside it.
struct ImportedRecipe {
    var parsed: ParsedRecipe
    var photo: UIImage?
}

extension RecipeImporter {
    /// Photos or screenshots: one recipe across several photos, several recipes, or several
    /// recipes on one photo. Returns every recipe found.
    static func importImages(_ images: [UIImage]) async throws -> [ImportedRecipe] {
        guard !images.isEmpty else { throw DocumentText.TextError.noText }

        var pages: [String] = []
        for image in images { pages.append(try await DocumentText.recognizeText(in: image)) }
        guard pages.joined().trimmingCharacters(in: .whitespacesAndNewlines).count > 20 else { throw DocumentText.TextError.noText }

        let found = RecipeSplitter.split(pages: pages).compactMap { piece -> ImportedRecipe? in
            let parsed = TextRecipeParser.parse(piece.text)
            return parsed.looksValid ? ImportedRecipe(parsed: parsed, photo: images[piece.firstPage]) : nil
        }
        if !found.isEmpty { return found }
        // Nothing split cleanly: fall back to reading everything as one recipe.
        let whole = TextRecipeParser.parse(pages.joined(separator: "\n"))
        guard whole.looksValid else { throw ImportError.noRecipeFound }
        return [ImportedRecipe(parsed: whole, photo: images.first)]
    }

    /// Files from AirDrop, "Open in…", or the Share menu: photos, PDFs, text or web pages.
    static func importFiles(_ urls: [URL]) async throws -> [ImportedRecipe] {
        var images: [UIImage] = []
        var texts: [String] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let type = UTType(filenameExtension: url.pathExtension.lowercased())

            if type?.conforms(to: .image) == true {
                guard let image = UIImage(contentsOfFile: url.path) else { throw DocumentText.TextError.unreadable }
                images.append(image)
            } else if type?.conforms(to: .pdf) == true {
                // Scanned PDFs (no text layer) are treated like photos, so a scanned cookbook
                // chapter can hold several recipes.
                let pdf = try await DocumentText.pdfContents(url)
                if let text = pdf.text { texts.append(text) } else { images += pdf.pageImages }
            } else if type?.conforms(to: .html) == true {
                let html = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                if let parsed = JSONLDRecipeParser.parse(html: html, sourceURL: nil) { return [ImportedRecipe(parsed: parsed)] }
                texts.append(HTMLText.pageText(html))
            } else {
                guard let s = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else {
                    throw DocumentText.TextError.unreadable
                }
                texts.append(s)
            }
        }

        var results: [ImportedRecipe] = []
        if !images.isEmpty { results += try await importImages(images) }
        if !texts.isEmpty {
            // A text file holding just a link is treated as a link.
            results.append(ImportedRecipe(parsed: try await importRecipe(from: texts.joined(separator: "\n\n"))))
        }
        return results
    }
}
