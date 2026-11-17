import SwiftUI

struct RootView: View {
    @Environment(HubModel.self) private var hub
    @Environment(TimerStore.self) private var timers
    @Environment(SceneRunner.self) private var sceneRunner
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.keepAwake) private var keepAwake = true
    @AppStorage(SettingsKey.hasSeenOnboarding) private var hasSeenOnboarding = false
    @State private var showingOnboarding = false

    var body: some View {
        @Bindable var hub = hub
        TabView(selection: $hub.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(AppTab.home)
            RecipeListView()
                .tabItem { Label("Recipes", systemImage: "book.closed.fill") }.tag(AppTab.recipes)
            TimersView()
                .tabItem { Label("Timers", systemImage: "timer") }.tag(AppTab.timers)
                .badge(timers.timers.count)
            ShoppingListView()
                .tabItem { Label("Shopping", systemImage: "cart.fill") }.tag(AppTab.shopping)
            ScenesView()
                .tabItem { Label("Scenes", systemImage: "lightbulb.2.fill") }.tag(AppTab.scenes)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(AppTab.settings)
        }
        .overlay(alignment: .top) { ToastView() }
        .overlay { RingingTimersOverlay() }
        .fullScreenCover(isPresented: $showingOnboarding) { OnboardingView() }
        .onAppear {
            #if DEBUG
            // App Store screenshots: sample data, and skip the tour unless it's being captured.
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-screenshotSeed") {
                hub.seedScreenshotData(timers: timers)
                hasSeenOnboarding = !args.contains("-showOnboarding")
            }
            #endif
            if !hasSeenOnboarding { showingOnboarding = true }
            hub.server.onRecipe = { [weak hub] input in
                guard let hub else { throw CancellationError() }
                return try await hub.receiveRecipe(input)
            }
            hub.server.onPhotos = { [weak hub] images in
                guard let hub else { throw CancellationError() }
                return try await hub.receiveRecipes(.images(images))
            }
            hub.server.onTimer = { [weak timers, weak hub] label, seconds in
                timers?.start(label: label, seconds: seconds)
                hub?.show(Toast(message: "\(label) started", symbol: "timer"))
            }
            // The view is appearing, so the app is in the foreground. Don't trust the scenePhase
            // captured here: on a cold launch it can still read .background, which used to
            // stop the server right after it started.
            UIApplication.shared.isIdleTimerDisabled = keepAwake
            hub.updateServer(active: true)
            Task { await hub.processInbox() }
            #if DEBUG
            // Screenshot/testing aid: launch with `-debugOpenURL kitchenhub://...`.
            if let s = UserDefaults.standard.string(forKey: "debugOpenURL"), let url = URL(string: s) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { handle(url) }
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in applyPhase(phase) }
        .onOpenURL(perform: handle)
        .onChange(of: hub.pendingSceneName) { _, name in
            guard let name else { return }
            hub.pendingSceneName = nil
            if let scene = hub.scene(named: name) {
                Task { await sceneRunner.run(scene) }
                hub.show(Toast(message: "Running \(scene.name)", symbol: scene.symbol))
            }
        }
        .onChange(of: keepAwake) { _, _ in applyPhase(scenePhase) }
    }

    /// kitchenhub://tab/timers · kitchenhub://recipe/latest · kitchenhub://recipe/<uuid or title>
    /// kitchenhub://add?url=<link> · kitchenhub://timer?minutes=10&label=Pasta · kitchenhub://scene/<name>
    private func handle(_ url: URL) {
        if url.isFileURL {
            // A file AirDropped to the iPad or sent with "Open in Kitchen Hub". iOS copies it into
            // our Documents/Inbox, so delete it once it's imported.
            Task {
                _ = try? await hub.receiveRecipes(.files([url]))
                try? FileManager.default.removeItem(at: url)
            }
            return
        }
        guard url.scheme == "kitchenhub" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        let query = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        switch url.host {
        case "tab":
            let tabs: [String: AppTab] = ["home": .home, "recipes": .recipes, "timers": .timers,
                                          "shopping": .shopping, "scenes": .scenes, "settings": .settings]
            if let t = parts.first.flatMap({ tabs[$0] }) { hub.selectedTab = t }
        case "recipe":
            if parts.first == "latest", let r = hub.latestRecipe() { hub.open(recipeID: r.id) }
            else if let id = parts.first.flatMap(UUID.init(uuidString:)) { hub.open(recipeID: id) }
            else if let title = parts.first, let r = hub.recipe(titled: title) { hub.open(recipeID: r.id) }
        case "add":
            if let input = query["url"] ?? query["text"] {
                Task { _ = try? await hub.receiveRecipe(input) }
            }
        case "timer":
            if let m = Double(query["minutes"] ?? "") {
                timers.start(label: query["label"] ?? "Timer", seconds: m * 60)
                hub.selectedTab = .timers
            }
        case "scene":
            if let name = parts.first { hub.pendingSceneName = name }
        default: break
        }
    }

    private func applyPhase(_ phase: ScenePhase) {
        UIApplication.shared.isIdleTimerDisabled = keepAwake && phase == .active
        if phase == .active {
            hub.updateServer(active: true)
            Task { await hub.processInbox() }
        }
        if phase == .background { hub.updateServer(active: false) }
    }
}

struct ToastView: View {
    @Environment(HubModel.self) private var hub

    var body: some View {
        if let toast = hub.toast {
            HStack(spacing: 14) {
                Image(systemName: toast.symbol)
                    .font(.title2)
                    .foregroundStyle(toast.isError ? Color.red : Color.accentColor)
                Text(toast.message).font(.headline).lineLimit(2)
                if let id = toast.recipeID {
                    Button("Open") {
                        hub.toast = nil
                        hub.open(recipeID: id)
                    }
                    .buttonStyle(.borderedProminent)
                } else if toast.opensRecipeList {
                    Button("Show") {
                        hub.toast = nil
                        hub.openRecipeList()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button { withAnimation { hub.toast = nil } } label: {
                    Image(systemName: "xmark").font(.subheadline.bold())
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// Full-screen, impossible-to-miss alert when a timer goes off.
struct RingingTimersOverlay: View {
    @Environment(TimerStore.self) private var timers

    var body: some View {
        let ringing = timers.ringing
        if !ringing.isEmpty {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 28) {
                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.orange)
                        .symbolEffect(.bounce, options: .repeating)
                    VStack(spacing: 8) {
                        ForEach(ringing) { t in
                            Text(t.label).font(.system(size: 44, weight: .bold, design: .rounded))
                        }
                        Text("Time's up!").font(.title2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 16) {
                        if ringing.count == 1, let t = ringing.first {
                            Button { timers.add(60, to: t.id) } label: {
                                Label("+1 min", systemImage: "plus").frame(minWidth: 140)
                            }
                            .buttonStyle(.bordered)
                        }
                        Button { timers.dismissAllRinging() } label: {
                            Label("Stop", systemImage: "stop.fill").frame(minWidth: 180)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .controlSize(.large)
                    .font(.title2.bold())
                }
                .padding(48)
                .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
            }
            .transition(.opacity)
        }
    }
}
