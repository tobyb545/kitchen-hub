import Foundation
import SwiftData

@Model
final class ShoppingItem {
    var id: UUID = UUID()
    var text: String = ""
    var fromRecipe: String?
    var isDone: Bool = false
    var createdAt: Date = Date()

    init(text: String, fromRecipe: String? = nil) {
        self.text = text
        self.fromRecipe = fromRecipe
        self.createdAt = Date()
    }
}
