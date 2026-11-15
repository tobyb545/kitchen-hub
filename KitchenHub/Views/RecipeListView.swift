import SwiftUI
import SwiftData
import PhotosUI
import VisionKit

struct RecipeListView: View {
    @Environment(HubModel.self) private var hub
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @State private var search = ""
    @State private var favouritesOnly = false
    @State private var showingAdd = false

    private var filtered: [Recipe] {
        recipes.filter { r in
            (!favouritesOnly || r.isFavorite) &&
            (search.isEmpty || r.title.localizedCaseInsensitiveContains(search)
             || r.ingredients.contains { $0.text.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        @Bindable var hub = hub
        NavigationStack(path: $hub.recipePath) {
            ScrollView {
                if recipes.isEmpty {
                    ContentUnavailableView {
                        Label("No recipes yet", systemImage: "book.closed")
                    } description: {
                        Text("Tap + to paste a link or recipe text, or send one from your phone using the address on the Home screen.")
                    } actions: {
                        Button("Add a recipe") { showingAdd = true }.buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 80)
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search).padding(.top, 80)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 20)], spacing: 20) {
                        ForEach(filtered) { r in
                            NavigationLink(value: r.id) { RecipeCard(recipe: r) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { r.isFavorite.toggle() } label: {
                                        Label(r.isFavorite ? "Unfavourite" : "Favourite", systemImage: "heart")
                                    }
                                }
                        }
                    }
                    .padding(28)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Recipes")
            .searchable(text: $search, prompt: "Search recipes or ingredients")
            .toolbar {
                ToolbarItemGroup {
                    Toggle(isOn: $favouritesOnly) { Label("Favourites", systemImage: favouritesOnly ? "heart.fill" : "heart") }
                        .toggleStyle(.button)
                    Button { showingAdd = true } label: { Label("Add recipe", systemImage: "plus") }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let recipe = hub.recipe(id: id) {
                    RecipeDetailView(recipe: recipe)
                } else {
                    ContentUnavailableView("Recipe not found", systemImage: "questionmark")
                }
            }
            .sheet(isPresented: $showingAdd) { AddRecipeView() }
        }
    }
}

struct RecipeCard: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipeImage(url: recipe.imageURL)
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if recipe.isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.35), in: Circle())
                            .padding(10)
                    }
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title).font(.headline).lineLimit(2, reservesSpace: true)
                HStack(spacing: 10) {
                    if let m = recipe.displayTotalMinutes { Label(m.minutesText, systemImage: "clock") }
                    if let s = recipe.servings { Label("\(s)", systemImage: "person.2") }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text(recipe.sourceHost ?? "Added \(recipe.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct AddRecipeView: View {
    @Environment(HubModel.self) private var hub
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var working = false
    @State private var error: String?
    @State private var scanning = false
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $input)
                        .frame(minHeight: 200)
                        .font(.body)
                        .overlay(alignment: .topLeading) {
                            if input.isEmpty {
                                Text("Paste a recipe link, or the whole recipe as text…")
                                    .foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    Button {
                        if let s = UIPasteboard.general.string { input = s }
                    } label: { Label("Paste from clipboard", systemImage: "doc.on.clipboard") }
                } header: {
                    Text("Link or text")
                } footer: {
                    Text("Tip: copy a link on your iPhone, then tap Paste here. Universal Clipboard carries it across.")
                }

                Section {
                    if VNDocumentCameraViewController.isSupported {
                        Button { scanning = true } label: {
                            Label("Scan a cookbook page or recipe card", systemImage: "doc.viewfinder")
                        }
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
                        Label("Choose photos or screenshots (up to 10)", systemImage: "photo.on.rectangle")
                    }
                } header: {
                    Text("From a photo")
                } footer: {
                    Text("Pick one recipe spread over several screenshots, or several different recipes at once, and each becomes its own recipe. Clear, printed text works best; handwriting may need tidying with Edit afterwards.")
                }

                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
            }
            .disabled(working)
            .overlay {
                if working {
                    ProgressView("Reading recipe…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .navigationTitle("Add recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { Task { await run(.input(input)) } }
                        .disabled(working || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(working)
            .fullScreenCover(isPresented: $scanning) {
                DocumentScanner { images in
                    scanning = false
                    if !images.isEmpty { Task { await run(.images(images)) } }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var images: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            images.append(image)
                        }
                    }
                    photoItems = []
                    if images.isEmpty { error = "Couldn't load those photos." } else { await run(.images(images)) }
                }
            }
        }
    }

    private func run(_ source: HubModel.RecipeSource) async {
        working = true
        error = nil
        do {
            let recipes = try await hub.importRecipes(source)
            dismiss()
            if recipes.count == 1, let r = recipes.first {
                hub.open(recipeID: r.id)
            } else {
                hub.openRecipeList()
                hub.announce(recipes)
            }
        } catch {
            self.error = error.localizedDescription
        }
        working = false
    }
}

/// The system document camera: auto-detects the page edges and flattens it.
struct DocumentScanner: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map(scan.imageOfPage(at:)))
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish([]) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish([]) }
    }
}
