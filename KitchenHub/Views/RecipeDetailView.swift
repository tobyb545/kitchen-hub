import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    @Environment(HubModel.self) private var hub
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Bindable var recipe: Recipe

    @State private var servings: Int = 0
    @State private var checked: Set<UUID> = []
    @State private var cooking = false
    @State private var editing = false
    @State private var confirmDelete = false
    @AppStorage(SettingsKey.recipeMeasures) private var measures: UnitConverter.Measures = .original
    @AppStorage(SettingsKey.recipeTemperature) private var temperature: UnitConverter.Temperature = .original

    private var baseServings: Int { recipe.servings ?? 0 }
    private var factor: Double { baseServings > 0 && servings > 0 ? Double(servings) / Double(baseServings) : 1 }

    /// An ingredient line as shown: scaled for servings, then converted to the chosen units.
    private func display(ingredient text: String) -> String {
        UnitConverter.convertIngredient(IngredientScaler.scale(text, by: factor), measures: measures, temperature: temperature)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        ingredientsCard.frame(width: 380)
                        // Without an ideal width, long steps report a huge ideal size and
                        // ViewThatFits falls back to the stacked layout even on a wide iPad.
                        methodCard.frame(minWidth: 420, idealWidth: 520, maxWidth: .infinity)
                    }
                    VStack(spacing: 24) { ingredientsCard; methodCard }
                }
                if !recipe.notes.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(title: "Notes", symbol: "note.text")
                            Text(recipe.notes)
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup {
                Button { recipe.isFavorite.toggle() } label: {
                    Label("Favourite", systemImage: recipe.isFavorite ? "heart.fill" : "heart")
                }
                Menu {
                    Button { editing = true } label: { Label("Edit recipe", systemImage: "pencil") }
                    Button { addMissingToShopping() } label: { Label("Add unticked to shopping list", systemImage: "cart.badge.plus") }
                    if let s = recipe.sourceURL, let url = URL(string: s) {
                        Button { openURL(url) } label: { Label("Open original page", systemImage: "safari") }
                        ShareLink(item: url) { Label("Share link", systemImage: "square.and.arrow.up") }
                    }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete recipe", systemImage: "trash") }
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
        }
        .onAppear {
            if servings == 0 { servings = baseServings }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-debugCookMode") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { cooking = true }
            }
            #endif
        }
        .fullScreenCover(isPresented: $cooking) { CookModeView(recipe: recipe, factor: factor) }
        .sheet(isPresented: $editing) { EditRecipeView(recipe: recipe) }
        .confirmationDialog("Delete “\(recipe.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                RecipePhotoStore.delete(recipe.imageURL)
                context.delete(recipe)
                try? context.save()
                hub.recipePath = []
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 24) {
            if recipe.imageURL != nil {
                RecipeImage(url: recipe.imageURL)
                    .frame(width: 280, height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(recipe.title).font(.system(size: 38, weight: .bold, design: .serif))
                if !recipe.summary.isEmpty {
                    Text(recipe.summary).font(.title3).foregroundStyle(.secondary).lineLimit(4)
                }
                if let host = recipe.sourceHost {
                    Label(host, systemImage: "link").font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if let p = recipe.prepMinutes { MetaPill(symbol: "knife", text: "Prep \(p.minutesText)") }
                    if let c = recipe.cookMinutes { MetaPill(symbol: "flame", text: "Cook \(c.minutesText)") }
                    if let t = recipe.displayTotalMinutes { MetaPill(symbol: "clock", text: "Total \(t.minutesText)") }
                    if let y = recipe.yieldText, recipe.servings == nil { MetaPill(symbol: "person.2", text: y) }
                }
                UnitsControls(measures: $measures, temperature: $temperature,
                              showTemperature: UnitConverter.containsTemperature((recipe.steps + recipe.ingredients).map(\.text)))
                Spacer(minLength: 0)
                Button {
                    recipe.lastCookedAt = Date()
                    cooking = true
                } label: {
                    Label("Start cooking", systemImage: "play.fill").font(.title3.bold()).padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Ingredients

    private var ingredientsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionTitle(title: "Ingredients", symbol: "basket.fill")
                    Spacer()
                    if baseServings > 0 {
                        Stepper(value: $servings, in: 1...48) {
                            Text("Serves \(servings)").font(.headline).monospacedDigit()
                        }
                        .fixedSize()
                    }
                }
                if factor != 1 {
                    Text("Quantities scaled ×\(IngredientScaler.format(factor)) from \(baseServings)")
                        .font(.caption).foregroundStyle(Color.accentColor)
                }
                ForEach(grouped(recipe.ingredients)) { group in
                    if let section = group.section { Text(section).font(.headline).padding(.top, 6) }
                    ForEach(group.lines) { line in
                        Button {
                            if checked.contains(line.id) { checked.remove(line.id) } else { checked.insert(line.id) }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Image(systemName: checked.contains(line.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(checked.contains(line.id) ? Color.accentColor : Color.secondary)
                                Text(display(ingredient: line.text))
                                    .strikethrough(checked.contains(line.id))
                                    .foregroundStyle(checked.contains(line.id) ? .secondary : .primary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .font(.title3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Method

    private var methodCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(title: "Method", symbol: "list.number")
                let steps = recipe.steps
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    if let section = step.section, index == 0 || steps[index - 1].section != section {
                        Text(section).font(.headline).padding(.top, 4)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(index + 1)")
                            .font(.headline.monospacedDigit())
                            .frame(width: 34, height: 34)
                            .background(Color.accentColor.opacity(0.15), in: Circle())
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(UnitConverter.convertTemperatures(in: step.text, to: temperature)).font(.title3)
                            let durations = DurationDetector.matches(in: step.text)
                            if !durations.isEmpty {
                                HStack { ForEach(durations) { TimerChip(match: $0, label: "\(recipe.title) · step \(index + 1)") } }
                            }
                        }
                    }
                }
            }
        }
    }

    private func addMissingToShopping() {
        let lines = recipe.ingredients.filter { !checked.contains($0.id) }.map { display(ingredient: $0.text) }
        guard !lines.isEmpty else { return }
        hub.addToShoppingList(lines, from: recipe.title)
    }
}

/// "Measures: As written | Cups | Grams" and "Oven: As written | °F | °C" segmented controls.
struct UnitsControls: View {
    @Binding var measures: UnitConverter.Measures
    @Binding var temperature: UnitConverter.Temperature
    var showTemperature = true

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { measuresPicker; if showTemperature { temperaturePicker } }
            VStack(alignment: .leading, spacing: 10) { measuresPicker; if showTemperature { temperaturePicker } }
        }
    }

    private var measuresPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "scalemass").foregroundStyle(.secondary)
            Picker("Measures", selection: $measures) {
                ForEach(UnitConverter.Measures.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).fixedSize()
        }
    }

    private var temperaturePicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "thermometer.medium").foregroundStyle(.secondary)
            Picker("Oven temperature", selection: $temperature) {
                ForEach(UnitConverter.Temperature.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).fixedSize()
        }
    }
}

struct LineGroup: Identifiable {
    let id: Int
    let section: String?
    var lines: [RecipeLine]
}

/// Groups consecutive lines by section, keeping order.
func grouped(_ lines: [RecipeLine]) -> [LineGroup] {
    var out: [LineGroup] = []
    for line in lines {
        if let last = out.last, last.section == line.section {
            out[out.count - 1].lines.append(line)
        } else {
            out.append(LineGroup(id: out.count, section: line.section, lines: [line]))
        }
    }
    return out
}

struct EditRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var recipe: Recipe
    @State private var title = ""
    @State private var summary = ""
    @State private var servings = 0
    @State private var ingredients = ""
    @State private var steps = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") { TextField("Title", text: $title) }
                Section("Description") { TextField("Optional", text: $summary, axis: .vertical) }
                Section("Serves") { Stepper(servings == 0 ? "Not set" : "\(servings)", value: $servings, in: 0...48) }
                Section {
                    TextEditor(text: $ingredients).frame(minHeight: 200)
                } header: { Text("Ingredients") } footer: { Text("One per line. A line ending in “:” starts a section, e.g. “For the sauce:”.") }
                Section {
                    TextEditor(text: $steps).frame(minHeight: 260)
                } header: { Text("Method") } footer: { Text("One step per line.") }
                Section("Notes") { TextEditor(text: $notes).frame(minHeight: 100) }
            }
            .navigationTitle("Edit recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); dismiss() } }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        title = recipe.title
        summary = recipe.summary
        servings = recipe.servings ?? 0
        ingredients = Self.text(from: recipe.ingredients)
        steps = Self.text(from: recipe.steps)
        notes = recipe.notes
    }

    private func save() {
        recipe.title = title.isEmpty ? recipe.title : title
        recipe.summary = summary
        recipe.servings = servings == 0 ? nil : servings
        recipe.ingredients = Self.lines(from: ingredients)
        recipe.steps = Self.lines(from: steps).map { RecipeLine(section: $0.section, text: TextRecipeParser.stripStepPrefix($0.text)) }
        recipe.notes = notes
    }

    static func text(from lines: [RecipeLine]) -> String {
        var out: [String] = []
        var current: String?
        for l in lines {
            if l.section != current {
                if let s = l.section { out.append("\(s):") }
                current = l.section
            }
            out.append(l.text)
        }
        return out.joined(separator: "\n")
    }

    static func lines(from text: String) -> [RecipeLine] {
        var section: String?
        var out: [RecipeLine] = []
        for raw in text.components(separatedBy: .newlines) {
            let t = raw.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            if t.hasSuffix(":"), t.count < 50 { section = String(t.dropLast()); continue }
            out.append(RecipeLine(section: section, text: t))
        }
        return out
    }
}
