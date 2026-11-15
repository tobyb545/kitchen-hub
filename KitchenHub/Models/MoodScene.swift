import Foundation
import SwiftData
import SwiftUI

/// One thing a scene does when tapped.
struct SceneAction: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        /// Fires an Alexa routine through Voice Monkey (voicemonkey.io).
        case alexaRoutine
        /// Calls any URL — IFTTT, Home Assistant, a smart plug's local API, etc.
        case webhook
        var id: String { rawValue }
        var title: String {
            switch self {
            case .alexaRoutine: return "Alexa routine"
            case .webhook: return "Web request"
            }
        }
    }

    var id = UUID()
    var kind: Kind = .alexaRoutine
    /// Voice Monkey "Routine Trigger" device ID.
    var deviceID: String = ""
    var url: String = ""
    var method: String = "GET"
    var body: String = ""

    var summary: String {
        switch kind {
        case .alexaRoutine: return deviceID.isEmpty ? "Alexa routine (not set up)" : "Alexa trigger “\(deviceID)”"
        case .webhook: return url.isEmpty ? "Web request (no URL)" : "\(method) \(URL(string: url)?.host ?? url)"
        }
    }

    var isConfigured: Bool {
        switch kind {
        case .alexaRoutine: return !deviceID.trimmingCharacters(in: .whitespaces).isEmpty
        case .webhook: return URL(string: url)?.scheme?.hasPrefix("http") == true
        }
    }
}

@Model
final class MoodScene {
    var id: UUID = UUID()
    var name: String = ""
    var symbol: String = "lightbulb.fill"
    var tint: String = SceneTint.amber.rawValue
    var sortOrder: Int = 0
    var actionsData: Data = Data()
    var lastRunAt: Date?

    init(name: String, symbol: String, tint: SceneTint, sortOrder: Int, actions: [SceneAction] = []) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.tint = tint.rawValue
        self.sortOrder = sortOrder
        self.actions = actions
    }

    var actions: [SceneAction] {
        get { (try? JSONDecoder().decode([SceneAction].self, from: actionsData)) ?? [] }
        set { actionsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var tintColor: Color { (SceneTint(rawValue: tint) ?? .amber).color }
}

enum SceneTint: String, CaseIterable, Identifiable {
    case amber, rose, violet, indigo, teal, green, slate
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .amber: return .orange
        case .rose: return .pink
        case .violet: return .purple
        case .indigo: return .indigo
        case .teal: return .teal
        case .green: return .green
        case .slate: return .gray
        }
    }
}

enum SceneDefaults {
    static let symbols = [
        "lightbulb.fill", "sun.max.fill", "moon.stars.fill", "sparkles", "flame.fill",
        "fork.knife", "wineglass.fill", "tv.fill", "music.note", "book.fill",
        "bed.double.fill", "power", "sunrise.fill", "party.popper.fill", "cup.and.saucer.fill", "leaf.fill",
    ]

    /// Starter scenes. Each points at a Voice Monkey trigger with a suggested ID; the user
    /// creates a matching trigger + Alexa routine (or edits the ID) to make it live.
    static func make() -> [MoodScene] {
        [
            MoodScene(name: "Cooking", symbol: "fork.knife", tint: .amber, sortOrder: 0,
                      actions: [SceneAction(kind: .alexaRoutine, deviceID: "kitchen-cooking")]),
            MoodScene(name: "Dinner", symbol: "wineglass.fill", tint: .rose, sortOrder: 1,
                      actions: [SceneAction(kind: .alexaRoutine, deviceID: "kitchen-dinner")]),
            MoodScene(name: "Evening", symbol: "moon.stars.fill", tint: .violet, sortOrder: 2,
                      actions: [SceneAction(kind: .alexaRoutine, deviceID: "kitchen-evening")]),
            MoodScene(name: "Movie Night", symbol: "tv.fill", tint: .indigo, sortOrder: 3,
                      actions: [SceneAction(kind: .alexaRoutine, deviceID: "kitchen-movie")]),
            MoodScene(name: "Good Morning", symbol: "sunrise.fill", tint: .teal, sortOrder: 4,
                      actions: [SceneAction(kind: .alexaRoutine, deviceID: "kitchen-morning")]),
            MoodScene(name: "All Off", symbol: "power", tint: .slate, sortOrder: 5,
                      actions: [SceneAction(kind: .alexaRoutine, deviceID: "kitchen-all-off")]),
        ]
    }
}
