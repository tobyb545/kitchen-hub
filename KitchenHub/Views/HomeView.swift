import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(HubModel.self) private var hub
    @Environment(TimerStore.self) private var timers
    @Query(sort: \MoodScene.sortOrder) private var scenes: [MoodScene]
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @State private var showingAdd = false
    @State private var showingConverter = false
    @State private var showingNewTimer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 24) {
                            leftColumn.frame(minWidth: 380)
                            rightColumn.frame(minWidth: 380)
                        }
                        VStack(spacing: 24) { leftColumn; rightColumn }
                    }
                }
                .padding(28)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAdd) { AddRecipeView() }
            .sheet(isPresented: $showingConverter) { ConverterView() }
            .sheet(isPresented: $showingNewTimer) { NewTimerSheet() }
        }
    }

    // MARK: - Header

    private var header: some View {
        TimelineView(.everyMinute) { context in
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 76, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("\(greeting(for: context.date)) · \(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                        .font(.title3).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 12) {
                    Button { showingConverter = true } label: { Label("Convert", systemImage: "scalemass") }
                        .buttonStyle(.bordered)
                    Button { showingAdd = true } label: { Label("Add recipe", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
        }
    }

    private func greeting(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    // MARK: - Columns

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            timersCard
            recentRecipes
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            scenesCard
            sendCard
        }
    }

    private var timersCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionTitle(title: "Timers", symbol: "timer")
                    Spacer()
                    Button { showingNewTimer = true } label: { Label("Custom", systemImage: "plus") }
                        .buttonStyle(.bordered)
                }
                if timers.timers.isEmpty {
                    Text("No timers running").foregroundStyle(.secondary)
                } else {
                    ForEach(timers.timers) { t in CompactTimerRow(timer: t) }
                }
                QuickTimerButtons()
            }
        }
    }

    private var scenesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionTitle(title: "Scenes", symbol: "lightbulb.2.fill")
                    Spacer()
                    Button("Edit") { hub.selectedTab = .scenes }
                }
                if scenes.isEmpty {
                    Text("Add scenes in the Scenes tab.").foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(scenes) { SceneTile(scene: $0, compact: true) }
                    }
                }
            }
        }
    }

    private var recentRecipes: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionTitle(title: "Recipes", symbol: "book.closed.fill")
                    Spacer()
                    Button("See all") { hub.selectedTab = .recipes }
                }
                if recipes.isEmpty {
                    Text("Send a recipe from your phone, or tap Add recipe.").foregroundStyle(.secondary)
                } else {
                    ForEach(recipes.prefix(4)) { r in
                        Button { hub.open(recipeID: r.id) } label: {
                            HStack(spacing: 14) {
                                RecipeImage(url: r.imageURL)
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title).font(.headline).lineLimit(1)
                                    Text([r.displayTotalMinutes?.minutesText, r.sourceHost].compactMap { $0 }.joined(separator: " · "))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var sendCard: some View {
        Card {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(title: "Send a recipe", symbol: "iphone.and.arrow.forward")
                    if let address = hub.server.address {
                        Text("On your phone (same Wi-Fi), scan the code or open:")
                            .foregroundStyle(.secondary)
                        Text(address).font(.title3.monospaced().bold()).textSelection(.enabled)
                    } else {
                        Text(serverMessage).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let address = hub.server.address {
                    QRCodeView(text: address)
                        .frame(width: 120, height: 120)
                        .padding(8)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var serverMessage: String {
        switch hub.server.state {
        case .failed(let why): return "Receiver isn't running: \(why)"
        case .stopped: return "The recipe receiver is off. Turn it on in Settings."
        default: return "Starting… (connect the iPad to Wi-Fi)"
        }
    }
}

struct QuickTimerButtons: View {
    @Environment(TimerStore.self) private var timers
    private let presets = [1, 3, 5, 10, 15, 20, 30, 45]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
            ForEach(presets, id: \.self) { m in
                Button { timers.start(label: "\(m) min timer", seconds: TimeInterval(m * 60)) } label: {
                    Text("\(m)m").font(.headline).frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
