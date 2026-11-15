import Foundation
import UIKit
import Vision
import PDFKit

/// Gets text out of photos and PDFs, entirely on the iPad (Apple's Vision text recognition).
enum DocumentText {
    enum TextError: LocalizedError {
        case unreadable, noText
        var errorDescription: String? {
            switch self {
            case .unreadable: return "Couldn't open that file."
            case .noText: return "Couldn't find any text in that. Try a sharper, well-lit photo."
            }
        }
    }

    static func recognizeText(in image: UIImage) async throws -> String {
        guard let cg = image.cgImage ?? redraw(image).cgImage else { throw TextError.unreadable }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request])
            return layout(request.results ?? [])
        }.value
    }

    /// A PDF's text layer, or (for a scanned PDF with no text) its pages as images to be read
    /// like photos.
    static func pdfContents(_ url: URL) async throws -> (text: String?, pageImages: [UIImage]) {
        guard let doc = PDFDocument(url: url) else { throw TextError.unreadable }
        let embedded = (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if embedded.count > 80 { return (embedded, []) }
        var images: [UIImage] = []
        for i in 0..<min(doc.pageCount, 10) {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = 2200 / max(bounds.width, bounds.height, 1)
            images.append(page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox))
        }
        return (nil, images)
    }

    // MARK: - Layout

    private struct Line {
        let text: String
        let box: CGRect // Vision coordinates: 0...1, origin bottom-left
    }

    /// Orders recognised lines for reading. Cookbooks often put ingredients and method in two
    /// columns; reading straight across would interleave them, so detect that and read the left
    /// column, then the right.
    private static func layout(_ observations: [VNRecognizedTextObservation]) -> String {
        let lines = observations.compactMap { o in o.topCandidates(1).first.map { Line(text: $0.string, box: o.boundingBox) } }
        func readingOrder(_ a: Line, _ b: Line) -> Bool {
            abs(a.box.midY - b.box.midY) < 0.008 ? a.box.minX < b.box.minX : a.box.midY > b.box.midY
        }
        let left = lines.filter { $0.box.maxX <= 0.55 }
        let right = lines.filter { $0.box.minX >= 0.45 && $0.box.maxX > 0.55 }
        let spanning = lines.filter { $0.box.minX < 0.45 && $0.box.maxX > 0.55 }

        guard left.count >= 4, right.count >= 4, spanning.count * 2 < left.count + right.count else {
            return lines.sorted(by: readingOrder).map(\.text).joined(separator: "\n")
        }
        // The columns start where BOTH sides have text. Anything above that (title, intro; even
        // a short title that only covers the left half) is a header and is read first.
        let columnsTop = min(left.map { $0.box.maxY }.max() ?? 1, right.map { $0.box.maxY }.max() ?? 1)
        func isHeader(_ l: Line) -> Bool { l.box.minY >= columnsTop - 0.005 }
        let header = lines.filter(isHeader).sorted(by: readingOrder)
        let below = spanning.filter { !isHeader($0) }.sorted(by: readingOrder)
        let body = left.filter { !isHeader($0) }.sorted(by: readingOrder) + right.filter { !isHeader($0) }.sorted(by: readingOrder)
        return (header + body + below).map(\.text).joined(separator: "\n")
    }

    private static func redraw(_ image: UIImage) -> UIImage {
        UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(at: .zero) }
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
