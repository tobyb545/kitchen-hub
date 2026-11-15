import SwiftUI

/// Full-screen, one-step-at-a-time view with huge text, readable from across the kitchen.
struct CookModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TimerStore.self) private var timers
    let recipe: Recipe
    let factor: Double

    @State private var stepIndex = 0
    @State private var showIngredients = true

    private var steps: [RecipeLine] { recipe.steps }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                if showIngredients {
                    ingredientsPanel
                        .frame(width: 320)
                        .transition(.move(edge: .leading))
                    Divider()
                }
                VStack(spacing: 0) {
                    if !timers.timers.isEmpty { timerStrip }
                    stepPager
                    controls
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(recipe.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Label("Done", systemImage: "xmark") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { withAnimation { showIngredients.toggle() } } label: {
                        Label("Ingredients", systemImage: "sidebar.left")
                    }
                }
            }
        }
    }

    private var stepPager: some View {
        TabView(selection: $stepIndex) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        HStack {
                            Text("Step \(index + 1) of \(steps.count)")
                                .font(.title3.weight(.semibold)).foregroundStyle(Color.accentColor)
                            if let s = step.section { Text("· \(s)").font(.title3).foregroundStyle(.secondary) }
                        }
                        Text(step.text)
                            .font(.system(size: 38, weight: .medium))
                            .lineSpacing(8)
                            .fixedSize(horizontal: false, vertical: true)
                        let durations = DurationDetector.matches(in: step.text)
                        if !durations.isEmpty {
                            HStack(spacing: 12) {
                                ForEach(durations) { TimerChip(match: $0, label: "Step \(index + 1)", large: true) }
                            }
                        }
                    }
                    .padding(48)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var controls: some View {
        HStack(spacing: 20) {
            Button { withAnimation { stepIndex = max(0, stepIndex - 1) } } label: {
                Label("Back", systemImage: "chevron.left").frame(minWidth: 160, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(stepIndex == 0)

            ProgressView(value: Double(stepIndex + 1), total: Double(max(1, steps.count)))
                .frame(maxWidth: 300)

            if stepIndex < steps.count - 1 {
                Button { withAnimation { stepIndex += 1 } } label: {
                    Label("Next", systemImage: "chevron.right").labelStyle(TrailingIconLabelStyle()).frame(minWidth: 160, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button { dismiss() } label: {
                    Label("Finished", systemImage: "checkmark").frame(minWidth: 160, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .font(.title2.bold())
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var ingredientsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ingredients").font(.title2.bold())
                ForEach(grouped(recipe.ingredients)) { group in
                    if let section = group.section { Text(section).font(.headline).padding(.top, 6) }
                    ForEach(group.lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(Color.accentColor)
                            Text(IngredientScaler.scale(line.text, by: factor))
                        }
                        .font(.title3)
                    }
                }
            }
            .padding(24)
        }
        .background(Color(.secondarySystemBackground))
    }

    private var timerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(timers.timers) { t in
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        HStack(spacing: 8) {
                            Image(systemName: t.isFinished ? "bell.fill" : "timer")
                            Text(t.label).lineLimit(1)
                            Text(t.isFinished ? "Done" : t.remaining(at: ctx.date).clockText).monospacedDigit().bold()
                        }
                        .font(.title3)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background((t.isFinished ? Color.red : Color.accentColor).opacity(0.15), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
        }
        .background(.bar)
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack { configuration.title; configuration.icon }
    }
}
