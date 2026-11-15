import Foundation

/// Lightweight HTML helpers. Deliberately avoids NSAttributedString's HTML importer, which
/// is slow, main-thread only and can make network requests.
enum HTMLText {
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "deg": "°", "frac12": "½", "frac14": "¼",
        "frac34": "¾", "frac13": "⅓", "frac23": "⅔", "rsquo": "’", "lsquo": "‘", "rdquo": "”",
        "ldquo": "“", "times": "×", "eacute": "é", "egrave": "è", "agrave": "à", "ccedil": "ç",
        "ntilde": "ñ", "uuml": "ü", "ouml": "ö", "auml": "ä", "pound": "£", "euro": "€",
        "copy": "©", "reg": "®", "trade": "™", "bull": "•", "middot": "·",
    ]

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "&", let semi = s[i...].prefix(12).firstIndex(of: ";") {
                let entity = String(s[s.index(after: i)..<semi])
                if let decoded = decode(entity: entity) {
                    out += decoded
                    i = s.index(after: semi)
                    continue
                }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }

    private static func decode(entity: String) -> String? {
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            guard let v = UInt32(entity.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) else { return nil }
            return String(Character(u))
        }
        if entity.hasPrefix("#") {
            guard let v = UInt32(entity.dropFirst()), let u = Unicode.Scalar(v) else { return nil }
            return String(Character(u))
        }
        return namedEntities[entity.lowercased()]
    }

    /// Strips tags from a short HTML fragment (e.g. one instruction) and tidies whitespace.
    static func plain(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        t = decodeEntities(t)
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Converts a whole page into readable text with line breaks kept at block boundaries.
    static func pageText(_ html: String) -> String {
        var t = html
        for tag in ["script", "style", "noscript", "svg", "head", "nav", "footer", "iframe"] {
            t = t.replacingOccurrences(of: "<\(tag)\\b[^>]*>.*?</\(tag)>", with: " ",
                                       options: [.regularExpression, .caseInsensitive])
        }
        t = t.replacingOccurrences(of: "<!--.*?-->", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "<(br|/p|/li|/h[1-6]|/div|/tr|li|/section|/article)\\b[^>]*>", with: "\n",
                                   options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        t = decodeEntities(t)
        t = t.replacingOccurrences(of: "[ \\t\\u00A0]+", with: " ", options: .regularExpression)
        let lines = t.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    /// Reads `<meta property="og:..." content="...">` style tags.
    static func meta(_ name: String, in html: String) -> String? {
        let patterns = [
            "<meta[^>]+(?:property|name)=[\"']\(name)[\"'][^>]*content=[\"']([^\"']+)[\"']",
            "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]*(?:property|name)=[\"']\(name)[\"']",
        ]
        for p in patterns {
            if let r = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
               let m = r.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(m.range(at: 1), in: html) {
                return decodeEntities(String(html[range]))
            }
        }
        return nil
    }

    static func title(in html: String) -> String? {
        if let og = meta("og:title", in: html) { return og }
        guard let r = try? NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let m = r.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(m.range(at: 1), in: html) else { return nil }
        return plain(String(html[range]))
    }
}
