import SwiftUI

/// Kitchen conversions: weight, volume and oven temperature.
struct ConverterView: View {
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, CaseIterable, Identifiable {
        case weight = "Weight", volume = "Volume", temperature = "Oven"
        var id: String { rawValue }
    }

    struct Unit: Hashable {
        let name: String
        let factor: Double // to base unit (grams / millilitres)
    }

    private static let weights = [Unit(name: "g", factor: 1), Unit(name: "kg", factor: 1000),
                                  Unit(name: "oz", factor: 28.3495), Unit(name: "lb", factor: 453.592)]
    private static let volumes = [Unit(name: "ml", factor: 1), Unit(name: "litre", factor: 1000),
                                  Unit(name: "tsp", factor: 4.92892), Unit(name: "tbsp", factor: 14.7868),
                                  Unit(name: "cup (US)", factor: 236.588), Unit(name: "fl oz (UK)", factor: 28.4131),
                                  Unit(name: "pint (UK)", factor: 568.261)]

    @State private var kind: Kind = .weight
    @State private var amount: Double = 100
    @State private var unit = ConverterView.weights[0]
    @State private var celsius: Double = 180

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: kind) { _, k in unit = (k == .volume ? Self.volumes : Self.weights)[0] }

                if kind == .temperature {
                    Section("Celsius") {
                        Stepper(value: $celsius, in: 100...260, step: 10) {
                            Text("\(Int(celsius)) °C").font(.title2.bold())
                        }
                    }
                    Section("Equivalent") {
                        row("Fahrenheit", "\(Int((celsius * 9 / 5 + 32).rounded())) °F")
                        row("Fan oven", "\(Int(celsius - 20)) °C")
                        row("Gas mark", gasMark(celsius))
                    }
                } else {
                    let units = kind == .weight ? Self.weights : Self.volumes
                    Section("Amount") {
                        HStack {
                            TextField("Amount", value: $amount, format: .number)
                                .keyboardType(.decimalPad)
                                .font(.title2.bold())
                            Picker("Unit", selection: $unit) {
                                ForEach(units, id: \.self) { Text($0.name).tag($0) }
                            }
                            .labelsHidden()
                        }
                    }
                    Section("Equivalent") {
                        ForEach(units.filter { $0 != unit }, id: \.self) { u in
                            row(u.name, format(amount * unit.factor / u.factor))
                        }
                    }
                    if kind == .volume {
                        Section { Text("Cup measures are US cups (240 ml), as used by most online recipes.").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }
            .navigationTitle("Converter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) { Text(value).font(.title3.monospacedDigit().bold()) }
    }

    private func format(_ v: Double) -> String {
        v >= 100 ? String(Int(v.rounded())) : v.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func gasMark(_ c: Double) -> String {
        let table: [(Double, String)] = [(140, "1"), (150, "2"), (170, "3"), (180, "4"), (190, "5"),
                                         (200, "6"), (220, "7"), (230, "8"), (240, "9")]
        if c < 135 { return "¼–½" }
        return table.min { abs($0.0 - c) < abs($1.0 - c) }?.1 ?? "–"
    }
}
