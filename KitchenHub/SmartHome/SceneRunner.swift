import Foundation
import Observation

/// Runs a scene's actions.
///
/// Amazon doesn't offer a public API for third-party apps to control Alexa devices or run
/// routines, so Alexa control goes through Voice Monkey (voicemonkey.io): you create a
/// "Routine Trigger" device there, which appears in the Alexa app as a doorbell/sensor that
/// can start any routine. Calling Voice Monkey's API "presses" it, and Alexa runs the routine
/// — which can set your TP-Link plugs, bulbs, light strips, music, anything Alexa controls.
@Observable
@MainActor
final class SceneRunner {
    enum RunState: Equatable { case idle, running, succeeded, failed(String) }

    private(set) var states: [UUID: RunState] = [:]

    func state(for id: UUID) -> RunState { states[id] ?? .idle }

    func run(_ scene: MoodScene) async {
        let id = scene.id
        let actions = scene.actions
        guard !actions.isEmpty else {
            states[id] = .failed("No actions — edit this scene to add one.")
            return
        }
        states[id] = .running
        var errors: [String] = []
        for action in actions {
            do { try await Self.perform(action) } catch { errors.append(error.localizedDescription) }
        }
        scene.lastRunAt = Date()
        states[id] = errors.isEmpty ? .succeeded : .failed(errors.joined(separator: "\n"))
        let final = states[id]
        try? await Task.sleep(for: .seconds(errors.isEmpty ? 2.5 : 6))
        if states[id] == final { states[id] = .idle }
    }

    // MARK: - Actions

    enum ActionError: LocalizedError {
        case notConfigured(String), noToken, http(Int, String), rejected(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured(let what): return "\(what) isn't set up yet."
            case .noToken: return "Add your Voice Monkey API token in Settings › Smart Home."
            case .http(let code, let body): return "Request failed (\(code)) \(body)"
            case .rejected(let msg): return "Voice Monkey: \(msg)"
            }
        }
    }

    static func perform(_ action: SceneAction) async throws {
        switch action.kind {
        case .alexaRoutine: try await triggerVoiceMonkey(deviceID: action.deviceID)
        case .webhook: try await callWebhook(action)
        }
    }

    static func triggerVoiceMonkey(deviceID: String) async throws {
        let device = deviceID.trimmingCharacters(in: .whitespaces)
        guard !device.isEmpty else { throw ActionError.notConfigured("This Alexa trigger") }
        let token = Keychain.get(.voiceMonkeyToken)
        guard !token.isEmpty else { throw ActionError.noToken }

        // POST with a JSON body keeps the token out of URLs and logs.
        var request = URLRequest(url: URL(string: "https://api-v3.voicemonkey.io/trigger")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["token": token, "device": device])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if status == 401 || (json?["error"] as? String) == "INVALID_TOKEN" {
            throw ActionError.rejected("the API token wasn't accepted. Re-copy it from voicemonkey.io into Settings › Smart Home.")
        }
        guard status == 200 else {
            let msg = (json?["message"] as? String) ?? (json?["error"] as? String) ?? String(decoding: data.prefix(200), as: UTF8.self)
            throw ActionError.http(status, msg)
        }
        if let ok = json?["success"] as? Bool, !ok {
            throw ActionError.rejected((json?["message"] as? String) ?? "trigger failed")
        }
    }

    static func callWebhook(_ action: SceneAction) async throws {
        guard let url = URL(string: action.url.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true else {
            throw ActionError.notConfigured("This web request")
        }
        var request = URLRequest(url: url)
        request.httpMethod = action.method
        request.timeoutInterval = 15
        if action.method != "GET", !action.body.isEmpty {
            request.httpBody = Data(action.body.utf8)
            let looksJSON = action.body.trimmingCharacters(in: .whitespaces).hasPrefix("{")
            request.setValue(looksJSON ? "application/json" : "text/plain", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ActionError.http(status, String(decoding: data.prefix(120), as: UTF8.self))
        }
    }
}
