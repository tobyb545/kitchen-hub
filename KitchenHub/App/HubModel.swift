import SwiftUI
import SwiftData
import Observation

enum AppTab: Hashable { case home, recipes, timers, shopping, scenes, settings }

enum SettingsKey {
    static let keepAwake = "keepAwake"
    static let serverEnabled = "serverEnabled"
    static let serverPort = "serverPort"
    static let seededScenes = "seededScenes"
    // Recipe display units, remembered across recipes (UnitConverter.Measures / .Temperature).
    static let recipeMeasures = "recipeMeasures"
    static let recipeTemperature = "recipeTemperature"
    static let hasSeenOnboarding = "hasSeenOnboarding"
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var symbol: String
    var isError = false
    var recipeID: UUID?
    var opensRecipeList = false
}

/// App-wide state: navigation, the Wi-Fi server, and recipe importing (shared by the
/// in-app Add screen and recipes arriving over the network).
@Observable
@MainActor
final class HubModel {
    var selectedTab: AppTab = .home
    var recipePath: [UUID] = []
    var toast: Toast?
    /// Set by a kitchenhub://scene/<name> link; RootView runs it.
    var pendingSceneName: String?
    private(set) var importsInFlight = 0

    let server = HubServer()
    @ObservationIgnored let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        seedScenesIfNeeded()
        observeInbox()
    }

    // MARK: - Recipes

    /// Anything a recipe can come from.
    enum RecipeSource {
        case input(String)       // a link or pasted text
        case files([URL])        // photos, PDFs, text files (AirDrop / Open in / Share menu)
        case images([UIImage])   // camera scan or photo picker

        var isSlow: Bool { if case .input = self { return false } else { return true } }
    }

    @discardableResult
    func importRecipe(_ input: String) async throws -> Recipe {
        try await importRecipes(.input(input))[0]
    }

    /// Imports everything in a source. A link or text gives one recipe; a batch of photos or
    /// screenshots can give several.
    @discardableResult
    func importRecipes(_ source: RecipeSource) async throws -> [Recipe] {
        importsInFlight += 1
        defer { importsInFlight -= 1 }
        let found: [ImportedRecipe]
        switch source {
        case .input(let text):
            found = [ImportedRecipe(parsed: try await RecipeImporter.importRecipe(from: text))]
        case .files(let urls):
            found = try await RecipeImporter.importFiles(urls)
        case .images(let images):
            found = try await RecipeImporter.importImages(images)
        }
        guard !found.isEmpty else { throw RecipeImporter.ImportError.noRecipeFound }
        let recipes = found.map { item -> Recipe in
            var parsed = item.parsed
            if parsed.imageURL == nil, let photo = item.photo { parsed.imageURL = RecipePhotoStore.save(photo) }
            let recipe = Recipe(parsed: parsed)
            context.insert(recipe)
            return recipe
        }
        do { try context.save() } catch { print("Couldn't save recipes: \(error)") }
        return recipes
    }

    /// Called for recipes sent from another device or app: import, then announce on screen.
    @discardableResult
    func receiveRecipe(_ input: String) async throws -> String {
        try await receiveRecipes(.input(input)).joined(separator: ", ")
    }

    /// Returns the titles of the recipes added.
    @discardableResult
    func receiveRecipes(_ source: RecipeSource) async throws -> [String] {
        if source.isSlow { show(Toast(message: "Reading your recipes…", symbol: "doc.text.viewfinder")) }
        do {
            let recipes = try await importRecipes(source)
            announce(recipes)
            return recipes.map(\.title)
        } catch {
            show(Toast(message: error.localizedDescription, symbol: "exclamationmark.triangle.fill", isError: true))
            throw error
        }
    }

    func announce(_ recipes: [Recipe]) {
        if recipes.count == 1, let r = recipes.first {
            show(Toast(message: "New recipe: \(r.title)", symbol: "fork.knife", recipeID: r.id))
        } else {
            show(Toast(message: "Added \(recipes.count) recipes: \(recipes.map(\.title).joined(separator: ", "))",
                       symbol: "books.vertical.fill", opensRecipeList: true))
        }
    }

    func openRecipeList() {
        selectedTab = .recipes
        recipePath = []
    }

    // MARK: - Share-extension inbox

    @ObservationIgnored private var processingInbox = false

    /// Imports anything the Share extension left in the shared inbox.
    func processInbox() async {
        guard !processingInbox else { return }
        processingInbox = true
        defer { processingInbox = false }
        var seen = Set<UUID>()
        while let item = ImportInbox.pending().first(where: { !seen.contains($0.id) }) {
            seen.insert(item.id)
            let source: RecipeSource
            switch item.kind {
            case .link, .text: source = .input(item.text)
            case .files: source = .files(item.files.compactMap(ImportInbox.url(forFile:)))
            }
            _ = try? await receiveRecipes(source)
            ImportInbox.remove(item)
        }
    }

    /// Lets the Share extension wake us up when we're already on screen (Split View / Slide Over).
    private func observeInbox() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let hub = Unmanaged<HubModel>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in await hub.processInbox() }
            },
            ImportInbox.notificationName as CFString, nil, .deliverImmediately)
    }

    func open(recipeID: UUID) {
        selectedTab = .recipes
        recipePath = [recipeID]
    }

    func recipe(id: UUID) -> Recipe? {
        var d = FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    func recipe(titled title: String) -> Recipe? {
        let all = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        return all.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }
    }

    func latestRecipe() -> Recipe? {
        var d = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    func scene(named name: String) -> MoodScene? {
        let all = (try? context.fetch(FetchDescriptor<MoodScene>())) ?? []
        return all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            ?? all.first { $0.name.replacingOccurrences(of: " ", with: "-").caseInsensitiveCompare(name) == .orderedSame }
    }

    func addToShoppingList(_ lines: [String], from recipe: String?) {
        for line in lines { context.insert(ShoppingItem(text: line, fromRecipe: recipe)) }
        try? context.save()
        show(Toast(message: "Added \(lines.count) item\(lines.count == 1 ? "" : "s") to the shopping list", symbol: "cart.fill"))
    }

    func show(_ toast: Toast) {
        withAnimation(.spring) { self.toast = toast }
        let id = toast.id
        Task {
            try? await Task.sleep(for: .seconds(toast.recipeID == nil && !toast.opensRecipeList ? 4 : 8))
            if self.toast?.id == id { withAnimation { self.toast = nil } }
        }
    }

    // MARK: - Server lifecycle

    func updateServer(active: Bool) {
        let d = UserDefaults.standard
        let enabled = d.object(forKey: SettingsKey.serverEnabled) as? Bool ?? true
        let port = UInt16(clamping: d.object(forKey: SettingsKey.serverPort) as? Int ?? 8080)
        if active && enabled { server.start(port: port) } else { server.stop() }
    }

    // MARK: - Seed

    private func seedScenesIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: SettingsKey.seededScenes) else { return }
        SceneDefaults.make().forEach(context.insert)
        try? context.save()
        UserDefaults.standard.set(true, forKey: SettingsKey.seededScenes)
    }
}
