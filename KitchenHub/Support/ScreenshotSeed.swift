#if DEBUG
import SwiftUI
import SwiftData

/// Sample kitchen for App Store screenshots. Launch a Debug build with `-screenshotSeed`.
/// Replaces all recipes and shopping items, so never use it on a real device's data.
extension HubModel {
    func seedScreenshotData(timers: TimerStore) {
        try? context.delete(model: Recipe.self)
        try? context.delete(model: ShoppingItem.self)

        let now = Date()
        for (index, sample) in Self.samples.enumerated() {
            var parsed = ParsedRecipe(title: sample.title, summary: sample.summary)
            parsed.servings = sample.serves
            parsed.prepMinutes = sample.prep
            parsed.cookMinutes = sample.cook
            parsed.ingredients = sample.ingredients.map { RecipeLine(section: $0.0, text: $0.1) }
            parsed.steps = sample.steps.map { RecipeLine(text: $0) }
            parsed.sourceURL = sample.source
            let recipe = Recipe(parsed: parsed)
            recipe.imageURL = RecipePhotoStore.save(Self.photo(sample.emoji, sample.colors))
            // Newest first in the list: the first sample is the most recent.
            recipe.createdAt = now.addingTimeInterval(TimeInterval(-index * 86_400))
            recipe.isFavorite = sample.favourite
            if index < 3 { recipe.lastCookedAt = now.addingTimeInterval(TimeInterval(-index * 3 * 86_400)) }
            context.insert(recipe)
        }

        let shopping: [(String, String?, Bool)] = [
            ("1 whole chicken (about 1.6kg)", "Lemon & Herb Roast Chicken", false),
            ("2 unwaxed lemons", "Lemon & Herb Roast Chicken", false),
            ("Fresh thyme", "Lemon & Herb Roast Chicken", true),
            ("400ml tin coconut milk", "Thai Green Curry", false),
            ("Thai green curry paste", "Thai Green Curry", false),
            ("Jasmine rice", nil, false),
            ("3 ripe bananas", "Banana Bread", true),
            ("Free-range eggs", nil, false),
            ("Greek yoghurt", nil, false),
            ("Coffee beans", nil, true),
        ]
        for (i, item) in shopping.enumerated() {
            let s = ShoppingItem(text: item.0, fromRecipe: item.1)
            s.isDone = item.2
            s.createdAt = now.addingTimeInterval(TimeInterval(i))
            context.insert(s)
        }
        try? context.save()

        for t in timers.timers { timers.remove(t.id) }
        _ = timers.start(label: "Roast chicken", seconds: 52 * 60 + 18)
        _ = timers.start(label: "Rice", seconds: 9 * 60 + 41)
        _ = timers.start(label: "Rest the meat", seconds: 15 * 60)

        UserDefaults.standard.set(true, forKey: "scenesHelpDismissed")
    }

    /// A simple illustrated "photo": gradient with a large food emoji.
    private static func photo(_ emoji: String, _ colors: (UIColor, UIColor)) -> UIImage {
        let size = CGSize(width: 1200, height: 900)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [colors.0.cgColor, colors.1.cgColor] as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            let text = emoji as NSString
            let font = UIFont.systemFont(ofSize: 480)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let s = text.size(withAttributes: attrs)
            // Placed in the upper part, since recipe photos are top-aligned when cropped.
            text.draw(at: CGPoint(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2 - 40), withAttributes: attrs)
        }
    }

    private struct Sample {
        let title: String, summary: String, emoji: String, colors: (UIColor, UIColor)
        let serves: Int, prep: Int, cook: Int, favourite: Bool, source: String?
        let ingredients: [(String?, String)]
        let steps: [String]
    }

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> UIColor {
        UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    private static let samples: [Sample] = [
        Sample(title: "Lemon & Herb Roast Chicken",
               summary: "A golden, juicy Sunday roast with crisp lemony skin and a quick pan gravy.",
               emoji: "🍗", colors: (rgb(255, 196, 120), rgb(232, 120, 70)), serves: 4, prep: 15, cook: 80, favourite: true,
               source: "https://example.com/roast-chicken",
               ingredients: [(nil, "1 whole chicken (about 1.6kg)"), (nil, "2 unwaxed lemons"), (nil, "1 bulb garlic, halved"),
                             (nil, "Small bunch of thyme"), (nil, "50g butter, softened"), (nil, "2 tbsp olive oil"),
                             (nil, "800g baby potatoes, halved"),
                             ("For the gravy", "1 tbsp plain flour"), ("For the gravy", "300ml chicken stock")],
               steps: ["Heat the oven to 220°C (200°C fan). Take the chicken out of the fridge 30 minutes before cooking.",
                       "Mix the butter with the zest of one lemon and the thyme leaves. Push it under the skin of the breast.",
                       "Put the halved lemons and garlic inside the chicken. Toss the potatoes in the oil and arrange them around it.",
                       "Roast for 20 minutes, then turn the oven down to 190°C and roast for another 1 hour.",
                       "Rest the chicken under foil for 15 minutes while you make the gravy.",
                       "Stir the flour into the roasting tin juices, then whisk in the stock and simmer for 5 minutes."]),
        Sample(title: "Thai Green Curry",
               summary: "Fragrant, creamy and on the table in half an hour.",
               emoji: "🍛", colors: (rgb(190, 225, 140), rgb(90, 160, 90)), serves: 4, prep: 10, cook: 20, favourite: true, source: nil,
               ingredients: [(nil, "1 tbsp vegetable oil"), (nil, "3 tbsp Thai green curry paste"), (nil, "400ml coconut milk"),
                             (nil, "500g chicken thighs, sliced"), (nil, "150g green beans, trimmed"), (nil, "1 tbsp fish sauce"),
                             (nil, "1 tsp brown sugar"), (nil, "Handful of Thai basil"), (nil, "Jasmine rice, to serve")],
               steps: ["Heat the oil in a wok and fry the curry paste for 1 minute until fragrant.",
                       "Pour in half the coconut milk and bubble for 2 minutes, then add the chicken.",
                       "Add the rest of the coconut milk and simmer for 10 minutes.",
                       "Add the green beans and cook for 4 minutes until just tender.",
                       "Season with fish sauce and sugar, scatter over the basil, and serve with rice."]),
        Sample(title: "Banana Bread",
               summary: "Soft, moist and the best use for spotty bananas.",
               emoji: "🍌", colors: (rgb(255, 230, 140), rgb(220, 170, 90)), serves: 10, prep: 15, cook: 60, favourite: false, source: nil,
               ingredients: [(nil, "3 ripe bananas, mashed"), (nil, "½ cup butter, melted"), (nil, "¾ cup brown sugar"),
                             (nil, "2 eggs"), (nil, "1 tsp vanilla extract"), (nil, "1 ¾ cups plain flour"),
                             (nil, "1 tsp baking soda"), (nil, "½ cup walnuts, chopped")],
               steps: ["Preheat the oven to 350°F and line a loaf tin.",
                       "Mix the bananas, butter, sugar, eggs and vanilla until smooth.",
                       "Fold in the flour and baking soda, then the walnuts.",
                       "Bake for 55 minutes, until a skewer comes out clean.",
                       "Cool in the tin for 10 minutes before turning out."]),
        Sample(title: "Weeknight Spaghetti Bolognese",
               summary: "A rich, slow-tasting ragù that's ready in under an hour.",
               emoji: "🍝", colors: (rgb(255, 170, 140), rgb(200, 80, 70)), serves: 4, prep: 15, cook: 40, favourite: false, source: nil,
               ingredients: [(nil, "1 tbsp olive oil"), (nil, "1 onion, finely chopped"), (nil, "2 carrots, finely chopped"),
                             (nil, "2 garlic cloves, crushed"), (nil, "500g beef mince"), (nil, "2 x 400g tins chopped tomatoes"),
                             (nil, "1 tbsp tomato purée"), (nil, "400g spaghetti"), (nil, "Parmesan, to serve")],
               steps: ["Soften the onion and carrot in the oil for 10 minutes.",
                       "Add the garlic and mince and brown for 5 minutes.",
                       "Stir in the tomatoes and purée and simmer for 25 minutes.",
                       "Cook the spaghetti for 10 minutes, then toss with the sauce and top with Parmesan."]),
        Sample(title: "Shakshuka",
               summary: "Eggs gently baked in a smoky, spiced tomato sauce.",
               emoji: "🍳", colors: (rgb(255, 200, 150), rgb(230, 110, 80)), serves: 2, prep: 5, cook: 20, favourite: true, source: nil,
               ingredients: [(nil, "1 tbsp olive oil"), (nil, "1 red pepper, sliced"), (nil, "1 tsp smoked paprika"),
                             (nil, "1 tsp ground cumin"), (nil, "400g tin chopped tomatoes"), (nil, "4 eggs"),
                             (nil, "Feta and parsley, to serve")],
               steps: ["Fry the pepper in the oil for 5 minutes, then add the spices.",
                       "Add the tomatoes and simmer for 8 minutes until thick.",
                       "Make four wells, crack in the eggs, cover and cook for 6 minutes.",
                       "Crumble over the feta, scatter with parsley and serve with bread."]),
        Sample(title: "Chocolate Chip Cookies",
               summary: "Crisp edges, chewy middles.",
               emoji: "🍪", colors: (rgb(235, 200, 160), rgb(170, 110, 70)), serves: 16, prep: 15, cook: 12, favourite: false, source: nil,
               ingredients: [(nil, "1 cup butter, softened"), (nil, "¾ cup sugar"), (nil, "¾ cup brown sugar"), (nil, "2 eggs"),
                             (nil, "2 ¼ cups plain flour"), (nil, "1 tsp baking soda"), (nil, "2 cups chocolate chips")],
               steps: ["Heat the oven to 375°F.", "Cream the butter and sugars, then beat in the eggs.",
                       "Mix in the flour and baking soda, then the chocolate chips.",
                       "Bake spoonfuls for 10 minutes until golden at the edges."]),
    ]
}
#endif
