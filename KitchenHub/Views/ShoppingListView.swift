import SwiftUI
import SwiftData

struct ShoppingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ShoppingItem.createdAt) private var items: [ShoppingItem]
    @State private var newItem = ""
    @FocusState private var focused: Bool

    private var todo: [ShoppingItem] { items.filter { !$0.isDone } }
    private var done: [ShoppingItem] { items.filter(\.isDone) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor).font(.title2)
                        TextField("Add an item", text: $newItem)
                            .font(.title3)
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit(add)
                    }
                }
                if items.isEmpty {
                    Section {
                        Text("Add items here, or use “Add unticked to shopping list” on any recipe.")
                            .foregroundStyle(.secondary)
                    }
                }
                if !todo.isEmpty {
                    Section("To buy (\(todo.count))") {
                        ForEach(todo) { row($0) }
                            .onDelete { delete($0, from: todo) }
                    }
                }
                if !done.isEmpty {
                    Section("In the basket") {
                        ForEach(done) { row($0) }
                            .onDelete { delete($0, from: done) }
                    }
                }
            }
            .navigationTitle("Shopping list")
            .toolbar {
                if !done.isEmpty {
                    Button("Clear ticked") { done.forEach(context.delete) }
                }
                if !items.isEmpty {
                    ShareLink(item: todo.map { "• \($0.text)" }.joined(separator: "\n")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func row(_ item: ShoppingItem) -> some View {
        Button { withAnimation { item.isDone.toggle() } } label: {
            HStack(spacing: 14) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isDone ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text).font(.title3).strikethrough(item.isDone).foregroundStyle(item.isDone ? .secondary : .primary)
                    if let r = item.fromRecipe { Text(r).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func add() {
        let t = newItem.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        context.insert(ShoppingItem(text: t))
        newItem = ""
        focused = true
    }

    private func delete(_ offsets: IndexSet, from list: [ShoppingItem]) {
        offsets.map { list[$0] }.forEach(context.delete)
    }
}
