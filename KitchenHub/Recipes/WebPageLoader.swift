import Foundation
import WebKit
import UIKit

/// Loads a page in a real (hidden) WebKit view and returns its final HTML.
///
/// Some big recipe sites (AllRecipes, Serious Eats, other Dotdash Meredith sites) answer plain
/// HTTP requests with a JavaScript bot check instead of the recipe. A real browser engine
/// passes that check, so this is the fallback when the quick fetch finds no recipe.
@MainActor
final class WebPageLoader: NSObject, WKNavigationDelegate {
    static func html(for url: URL, timeout: TimeInterval = 25) async -> String? {
        let loader = WebPageLoader()
        return await loader.load(url, timeout: timeout)
    }

    private let webView: WKWebView

    private override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = .all
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 1200), configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    private func load(_ url: URL, timeout: TimeInterval) async -> String? {
        // Attached to the window (invisibly) so WebKit doesn't throttle its JavaScript.
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        webView.alpha = 0
        webView.isUserInteractionEnabled = false
        window?.insertSubview(webView, at: 0)
        defer {
            webView.stopLoading()
            webView.removeFromSuperview()
        }

        webView.load(URLRequest(url: url))
        let deadline = Date().addingTimeInterval(timeout)
        var lastHTML: String?
        // Poll: challenge pages reload themselves once they pass, so keep checking until the
        // recipe data shows up or we run out of time.
        while Date() < deadline {
            try? await Task.sleep(for: .seconds(1))
            guard !webView.isLoading else { continue }
            if let html = try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String {
                lastHTML = html
                if html.range(of: "\"Recipe\"", options: .caseInsensitive) != nil,
                   html.range(of: "application/ld+json", options: .caseInsensitive) != nil {
                    return html
                }
            }
        }
        return lastHTML
    }
}
