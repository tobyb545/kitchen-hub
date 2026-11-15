import SwiftUI
import SwiftData

struct ScenesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MoodScene.sortOrder) private var scenes: [MoodScene]
    @State private var editing: MoodScene?
    @State private var showingHelp = false
    @AppStorage("scenesHelpDismissed") private var helpDismissed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if Keychain.get(.voiceMonkeyToken).isEmpty && !helpDismissed {
                        Card {
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: "info.circle.fill").font(.title).foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Connect Alexa to use scenes").font(.headline)
                                    Text("Each scene presses a Voice Monkey trigger, which starts an Alexa routine that sets your TP-Link lights and plugs. It takes about 5 minutes to set up.")
                                        .foregroundStyle(.secondary)
                                    HStack {
                                        Button("Show me how") { showingHelp = true }.buttonStyle(.borderedProminent)
                                        Button("Hide") { helpDismissed = true }
                                    }
                                }
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 20)], spacing: 20) {
                        ForEach(scenes) { scene in
                            SceneTile(scene: scene, compact: false)
                                .contextMenu {
                                    Button { editing = scene } label: { Label("Edit", systemImage: "pencil") }
                                    Button(role: .destructive) { context.delete(scene) } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                        Button { addScene() } label: {
                            VStack(spacing: 10) {
                                Image(systemName: "plus").font(.system(size: 36, weight: .semibold))
                                Text("New scene").font(.headline)
                            }
                            .frame(maxWidth: .infinity, minHeight: 170)
                            .foregroundStyle(.secondary)
                            .background(RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8])).foregroundStyle(.tertiary))
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Tap a scene to run it. Long-press to edit or delete.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Scenes")
            .toolbar {
                Button { showingHelp = true } label: { Label("Setup guide", systemImage: "questionmark.circle") }
            }
            .sheet(item: $editing) { SceneEditorView(scene: $0) }
            .sheet(isPresented: $showingHelp) { AlexaSetupGuide() }
        }
    }

    private func addScene() {
        let scene = MoodScene(name: "New scene", symbol: "sparkles", tint: .amber,
                              sortOrder: (scenes.map(\.sortOrder).max() ?? 0) + 1,
                              actions: [SceneAction(kind: .alexaRoutine)])
        context.insert(scene)
        editing = scene
    }
}

struct SceneTile: View {
    @Environment(SceneRunner.self) private var runner
    let scene: MoodScene
    let compact: Bool

    var body: some View {
        let state = runner.state(for: scene.id)
        Button { Task { await runner.run(scene) } } label: {
            VStack(alignment: .leading, spacing: compact ? 8 : 14) {
                HStack {
                    Image(systemName: scene.symbol)
                        .font(.system(size: compact ? 26 : 38, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    Spacer()
                    statusIcon(state)
                }
                Spacer(minLength: 0)
                Text(scene.name)
                    .font(compact ? .headline : .title2.bold())
                    .lineLimit(1)
                if !compact {
                    if case .failed(let msg) = state {
                        Text(msg).font(.caption).lineLimit(3)
                    } else {
                        Text(scene.actions.first?.summary ?? "No actions").font(.caption).opacity(0.8).lineLimit(1)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(compact ? 14 : 20)
            .frame(maxWidth: .infinity, minHeight: compact ? 96 : 170, alignment: .leading)
            .background(
                LinearGradient(colors: [scene.tintColor, scene.tintColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: compact ? 20 : 28, style: .continuous))
            .scaleEffect(state == .running ? 0.97 : 1)
            .animation(.spring(duration: 0.3), value: state)
        }
        .buttonStyle(.plain)
        .disabled(state == .running)
        .accessibilityLabel("Run scene \(scene.name)")
    }

    @ViewBuilder private func statusIcon(_ state: SceneRunner.RunState) -> some View {
        switch state {
        case .running: ProgressView().tint(.white)
        case .succeeded: Image(systemName: "checkmark.circle.fill").font(.title2)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").font(.title2)
        case .idle: EmptyView()
        }
    }
}

struct SceneEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var scene: MoodScene
    @State private var actions: [SceneAction] = []
    @State private var testResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Scene") {
                    TextField("Name", text: $scene.name)
                    Picker("Colour", selection: $scene.tint) {
                        ForEach(SceneTint.allCases) { t in
                            Label(t.rawValue.capitalized, systemImage: "circle.fill").foregroundStyle(t.color).tag(t.rawValue)
                        }
                    }
                }
                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))], spacing: 12) {
                        ForEach(SceneDefaults.symbols, id: \.self) { s in
                            Button { scene.symbol = s } label: {
                                Image(systemName: s).font(.title2).frame(width: 48, height: 48)
                                    .background(scene.symbol == s ? scene.tintColor.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ForEach($actions) { $action in
                    Section {
                        Picker("Type", selection: $action.kind) {
                            ForEach(SceneAction.Kind.allCases) { Text($0.title).tag($0) }
                        }
                        switch action.kind {
                        case .alexaRoutine:
                            TextField("Voice Monkey trigger ID, e.g. kitchen-evening", text: $action.deviceID)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        case .webhook:
                            TextField("https://…", text: $action.url)
                                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Picker("Method", selection: $action.method) {
                                Text("GET").tag("GET"); Text("POST").tag("POST"); Text("PUT").tag("PUT")
                            }
                            if action.method != "GET" {
                                TextField("Body (optional, JSON or text)", text: $action.body, axis: .vertical)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                            }
                        }
                        Button("Test this action") { Task { await test(action) } }
                        Button("Remove action", role: .destructive) { actions.removeAll { $0.id == action.id } }
                    } header: {
                        Text("Action")
                    } footer: {
                        if action.kind == .alexaRoutine {
                            Text("Must match the ID of a Routine Trigger in your Voice Monkey console. Then, in the Alexa app, make a routine that starts “When this happens › Smart Home › \(action.deviceID.isEmpty ? "your trigger" : action.deviceID)” and set your lights/plugs.")
                        }
                    }
                }
                Section {
                    Button { actions.append(SceneAction()) } label: { Label("Add another action", systemImage: "plus") }
                }
                if let testResult {
                    Section("Test result") { Text(testResult) }
                }
            }
            .navigationTitle(scene.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        scene.actions = actions
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .onAppear { actions = scene.actions }
        }
    }

    private func test(_ action: SceneAction) async {
        testResult = "Running…"
        do {
            try await SceneRunner.perform(action)
            testResult = "✓ Worked. If nothing happened, check the Alexa routine is enabled."
        } catch {
            testResult = "✗ \(error.localizedDescription)"
        }
    }
}

struct AlexaSetupGuide: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Amazon doesn't let other apps control Alexa directly, so Kitchen Hub uses **Voice Monkey**, a free Alexa skill. Each scene presses a virtual button in Alexa, and an Alexa routine you create does the rest: your TP-Link bulbs, plugs, light strips, music, anything Alexa controls.")
                }
                Section("1 · Voice Monkey") {
                    step(1, "Go to voicemonkey.io and sign in with your Amazon account. This enables the Voice Monkey skill on your Alexa.")
                    step(2, "In the Voice Monkey console, open **Devices** and create a **Routine Trigger** for each scene. Give it the same ID as the scene uses, e.g. `kitchen-evening`.")
                    step(3, "Open **API Credentials**, copy your **API token**, and paste it into Kitchen Hub › Settings › Smart Home.")
                    Button("Open voicemonkey.io") { openURL(URL(string: "https://voicemonkey.io")!) }
                }
                Section("2 · Alexa app") {
                    step(4, "In the Alexa app, go to **More › Routines › +**.")
                    step(5, "Under **When this happens** choose **Smart Home** and pick the trigger, e.g. *kitchen-evening*.")
                    step(6, "Under **Add action** choose **Smart Home** and set your devices: dim the kitchen lights to 30%, turn on the lamp plug, warm white, and so on. You can add music or announcements too.")
                    step(7, "Save. Back in Kitchen Hub, tap the scene, or open it and use **Test this action**.")
                }
                Section("Other options") {
                    Text("A scene can also send a plain **web request**, for example to IFTTT, Home Assistant or a webhook. One scene can have several actions.")
                }
            }
            .navigationTitle("Connect Alexa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.headline).frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text)
        }
    }
}
