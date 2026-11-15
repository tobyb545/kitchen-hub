import Foundation
import Network
import UIKit
import Observation

/// A tiny HTTP server on the local Wi-Fi so any phone/laptop in the house can send recipes:
///
///   GET  /             – a "Send to Kitchen" web page (paste a link or recipe text)
///   POST /api/recipe   – JSON {"url": "..."} / {"text": "..."}, a form post, or a plain-text body
///   POST /api/photos   – JSON {"images": ["data:image/jpeg;base64,...", ...]} (one or several recipes)
///   POST /api/timer    – JSON {"minutes": 10, "label": "Pasta"}
///   GET  /api/status   – health check
///
/// Also advertised over Bonjour as "Kitchen Hub" (_http._tcp).
@Observable
@MainActor
final class HubServer {
    enum State: Equatable { case stopped, starting, running, failed(String) }

    private(set) var state: State = .stopped
    private(set) var port: UInt16 = 8080

    /// Set by the app: imports a recipe and returns its title.
    @ObservationIgnored var onRecipe: ((String) async throws -> String)?
    /// Set by the app: imports a batch of photos (one or several recipes) and returns the titles.
    @ObservationIgnored var onPhotos: (([UIImage]) async throws -> [String])?
    /// Set by the app: starts a timer.
    @ObservationIgnored var onTimer: ((String, TimeInterval) -> Void)?

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private let queue = DispatchQueue(label: "kitchenhub.server")

    var address: String? {
        guard state == .running, let ip = NetworkInfo.wifiIPv4() else { return nil }
        return "http://\(ip):\(port)"
    }

    func start(port: UInt16) {
        if listener != nil, self.port == port, state == .running || state == .starting { return }
        stop()
        self.port = port
        state = .starting
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            l.service = NWListener.Service(name: "Kitchen Hub", type: "_http._tcp")
            l.stateUpdateHandler = { [weak self] newState in
                Task { @MainActor in self?.listenerChanged(newState) }
            }
            l.newConnectionHandler = { [weak self] conn in
                guard let self else { return }
                HTTPConnection(connection: conn, queue: self.queue) { request in
                    await self.handle(request)
                }.start()
            }
            l.start(queue: queue)
            listener = l
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        state = .stopped
    }

    private func listenerChanged(_ s: NWListener.State) {
        switch s {
        case .ready: state = .running
        case .failed(let e):
            state = .failed(e.localizedDescription)
            listener?.cancel()
            listener = nil
        case .cancelled: if case .failed = state {} else { state = .stopped }
        default: break
        }
    }

    // MARK: - Routing

    private func handle(_ req: HTTPRequest) async -> HTTPResponse {
        switch (req.method, req.path) {
        case ("OPTIONS", _):
            return HTTPResponse(status: 204, body: Data())
        case ("GET", "/"), ("GET", "/index.html"):
            return .html(SendPage.html)
        case ("GET", "/api/status"):
            return .json(["ok": true, "app": "Kitchen Hub"])
        case ("POST", "/api/recipe"):
            guard let input = recipeInput(from: req), !input.isEmpty else {
                return .json(["ok": false, "error": "Send a 'url' or 'text'."], status: 400)
            }
            guard let onRecipe else { return .json(["ok": false, "error": "Not ready"], status: 503) }
            do {
                let title = try await onRecipe(input)
                return .json(["ok": true, "title": title])
            } catch {
                return .json(["ok": false, "error": error.localizedDescription], status: 422)
            }
        case ("POST", "/api/photos"):
            let obj = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any]
            let images = (obj?["images"] as? [String] ?? []).compactMap(Self.decodeDataURL).compactMap(UIImage.init(data:))
            guard !images.isEmpty else { return .json(["ok": false, "error": "No readable photos were sent."], status: 400) }
            guard let onPhotos else { return .json(["ok": false, "error": "Not ready"], status: 503) }
            do {
                let titles = try await onPhotos(images)
                return .json(["ok": true, "titles": titles, "title": titles.joined(separator: ", ")])
            } catch {
                return .json(["ok": false, "error": error.localizedDescription], status: 422)
            }
        case ("POST", "/api/timer"):
            let obj = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] ?? req.formFields
            let minutes = (obj["minutes"] as? Double) ?? Double(obj["minutes"] as? String ?? "") ?? 0
            let seconds = (obj["seconds"] as? Double) ?? Double(obj["seconds"] as? String ?? "") ?? 0
            let total = minutes * 60 + seconds
            guard total > 0 else { return .json(["ok": false, "error": "Send 'minutes' or 'seconds'."], status: 400) }
            onTimer?((obj["label"] as? String) ?? "Timer", total)
            return .json(["ok": true])
        default:
            return .json(["ok": false, "error": "Not found"], status: 404)
        }
    }

    private static func decodeDataURL(_ s: String) -> Data? {
        let base64 = s.range(of: "base64,").map { String(s[$0.upperBound...]) } ?? s
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }

    private func recipeInput(from req: HTTPRequest) -> String? {
        let contentType = req.headers["content-type"]?.lowercased() ?? ""
        if contentType.contains("json"),
           let obj = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] {
            return [(obj["url"] as? String), (obj["text"] as? String)]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
        }
        if contentType.contains("x-www-form-urlencoded") {
            let f = req.formFields
            return [f["url"] as? String, f["text"] as? String]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
        }
        return String(data: req.body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Minimal HTTP/1.1

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    var formFields: [String: Any] {
        guard let s = String(data: body, encoding: .utf8) else { return [:] }
        var out: [String: Any] = [:]
        for pair in s.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map {
                String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0)
            }
            if kv.count == 2 { out[kv[0]] = kv[1] }
        }
        return out
    }
}

struct HTTPResponse {
    var status: Int
    var contentType = "text/plain; charset=utf-8"
    var body: Data

    static func html(_ s: String) -> HTTPResponse {
        HTTPResponse(status: 200, contentType: "text/html; charset=utf-8", body: Data(s.utf8))
    }

    static func json(_ obj: [String: Any], status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "application/json",
                     body: (try? JSONSerialization.data(withJSONObject: obj)) ?? Data())
    }

    func serialized() -> Data {
        let reason = [200: "OK", 204: "No Content", 400: "Bad Request", 404: "Not Found", 413: "Payload Too Large",
                      422: "Unprocessable Entity", 503: "Service Unavailable"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Headers: Content-Type\r\n"
        head += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

/// Reads one request from a connection, hands it to the handler, writes the response, closes.
final class HTTPConnection {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let handler: (HTTPRequest) async -> HTTPResponse
    private var buffer = Data()
    private var selfRetain: HTTPConnection?
    private static let maxSize = 30 * 1024 * 1024 // photos

    init(connection: NWConnection, queue: DispatchQueue, handler: @escaping (HTTPRequest) async -> HTTPResponse) {
        self.connection = connection
        self.queue = queue
        self.handler = handler
    }

    func start() {
        selfRetain = self
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.selfRetain = nil
            default: break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { self.buffer.append(data) }
            if self.buffer.count > Self.maxSize {
                self.respond(HTTPResponse(status: 413, body: Data("Too large".utf8)))
                return
            }
            if let request = self.parse() {
                Task {
                    let response = await self.handler(request)
                    self.respond(response)
                }
            } else if isComplete || error != nil {
                self.connection.cancel()
            } else {
                self.receive()
            }
        }
    }

    private func respond(_ response: HTTPResponse) {
        connection.send(content: response.serialized(), completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })
    }

    /// Returns a request once headers and the full body (per Content-Length) have arrived.
    private func parse() -> HTTPRequest? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let head = String(data: buffer[buffer.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard buffer.count - (bodyStart - buffer.startIndex) >= length else { return nil }
        let body = buffer[bodyStart..<(bodyStart + length)]
        let rawPath = String(requestLine[1])
        let path = rawPath.split(separator: "?").first.map(String.init) ?? rawPath
        return HTTPRequest(method: String(requestLine[0]).uppercased(), path: path, headers: headers, body: Data(body))
    }
}

enum NetworkInfo {
    /// The iPad's IPv4 address on Wi-Fi (en0), e.g. "192.168.0.41".
    static func wifiIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var fallback: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let iface = ptr.pointee
            guard iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: iface.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(iface.ifa_addr, socklen_t(iface.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let ip = String(cString: host)
            if name == "en0" { return ip }
            if name.hasPrefix("en"), !ip.hasPrefix("169.254") { fallback = fallback ?? ip }
        }
        return fallback
    }
}
