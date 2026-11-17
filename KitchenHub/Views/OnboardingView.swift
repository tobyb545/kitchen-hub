import SwiftUI

/// Welcome tour shown on first launch (and from Settings › Show welcome tour).
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.recipeMeasures) private var measures: UnitConverter.Measures = .original
    @AppStorage(SettingsKey.recipeTemperature) private var temperature: UnitConverter.Temperature = .original
    @State private var page = 0

    struct Slide: Identifiable {
        let id: Int
        let symbol: String
        let colors: [Color]
        let title: String
        let body: String
        let points: [(String, String)]
    }

    static let slides: [Slide] = [
        Slide(id: 0, symbol: "frying.pan.fill", colors: [.orange, .red],
              title: "Welcome to Kitchen Hub",
              body: "Turn your iPad into the kitchen's command centre: recipes, timers, the shopping list and your lights, all in one place.",
              points: []),
        Slide(id: 1, symbol: "square.and.arrow.down.on.square.fill", colors: [.orange, .pink],
              title: "Send recipes from anywhere",
              body: "Kitchen Hub tidies any recipe into ingredients and steps, without the life story.",
              points: [("link", "Paste a link from any recipe website"),
                       ("square.and.arrow.up", "Use the Share menu or AirDrop"),
                       ("camera.viewfinder", "Scan a cookbook or add screenshots"),
                       ("wifi", "Send from your phone over Wi-Fi")]),
        Slide(id: 2, symbol: "play.rectangle.fill", colors: [.green, .teal],
              title: "Cook mode",
              body: "Big, one-step-at-a-time instructions you can read from across the kitchen.",
              points: [("timer", "Tap a time in any step to start a timer"),
                       ("person.2", "Scale servings up or down"),
                       ("cart", "Send missing ingredients to the shopping list")]),
        Slide(id: 3, symbol: "scalemass.fill", colors: [.blue, .indigo],
              title: "Your units, every time",
              body: "Switch any recipe between cups and grams, °F and °C. Choose your favourites now; you can change them on any recipe.",
              points: []),
        Slide(id: 4, symbol: "lightbulb.2.fill", colors: [.yellow, .orange],
              title: "Set the mood",
              body: "Scenes run your Alexa routines, so one tap sets the lights for cooking, dinner or a film night.",
              points: [("house", "Works with anything Alexa controls"),
                       ("questionmark.circle", "Setup takes about 5 minutes: see the Scenes tab")]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if page < Self.slides.count - 1 {
                    Button("Skip") { finish() }.font(.headline).padding(24)
                }
            }
            .frame(height: 72)

            TabView(selection: $page) {
                ForEach(Self.slides) { slide in
                    slideView(slide).tag(slide.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            HStack(spacing: 10) {
                ForEach(Self.slides) { slide in
                    Capsule()
                        .fill(slide.id == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: slide.id == page ? 28 : 10, height: 10)
                }
            }
            .animation(.spring(duration: 0.3), value: page)
            .padding(.bottom, 24)

            Button {
                if page < Self.slides.count - 1 { withAnimation { page += 1 } } else { finish() }
            } label: {
                Text(page < Self.slides.count - 1 ? "Continue" : "Get started")
                    .font(.title3.bold())
                    .frame(width: 320, height: 56)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.bottom, 48)
        }
        .background(Color(.systemBackground))
        #if DEBUG
        .onAppear { page = UserDefaults.standard.integer(forKey: "onboardingPage") }  // screenshot aid
        #endif
    }

    private func slideView(_ slide: Slide) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: slide.symbol)
                    .font(.system(size: 76, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 170, height: 170)
                    .background(LinearGradient(colors: slide.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 44, style: .continuous))
                    .shadow(color: slide.colors[0].opacity(0.35), radius: 24, y: 12)
                    .padding(.top, 20)

                VStack(spacing: 14) {
                    Text(slide.title)
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .multilineTextAlignment(.center)
                    Text(slide.body)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                }

                if !slide.points.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(slide.points, id: \.1) { symbol, text in
                            Label {
                                Text(text).font(.title3)
                            } icon: {
                                Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 32)
                            }
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 520, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                if slide.id == 3 {
                    VStack(spacing: 16) {
                        unitRow("Measures", symbol: "scalemass") {
                            Picker("Measures", selection: $measures) {
                                ForEach(UnitConverter.Measures.allCases) { Text($0.label).tag($0) }
                            }
                        }
                        unitRow("Oven", symbol: "thermometer.medium") {
                            Picker("Oven temperature", selection: $temperature) {
                                ForEach(UnitConverter.Temperature.allCases) { Text($0.label).tag($0) }
                            }
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 520)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity)
        }
    }

    private func unitRow<P: View>(_ title: String, symbol: String, @ViewBuilder picker: () -> P) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.headline)
            picker().pickerStyle(.segmented)
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: SettingsKey.hasSeenOnboarding)
        dismiss()
    }
}
