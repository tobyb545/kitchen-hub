import SwiftUI

struct TimersView: View {
    @Environment(TimerStore.self) private var timers
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Quick start").font(.headline)
                            QuickTimerButtons()
                        }
                    }
                    if timers.timers.isEmpty {
                        ContentUnavailableView("No timers", systemImage: "timer",
                                               description: Text("Start one above, tap a time in any recipe step, or send one from your phone."))
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20)], spacing: 20) {
                            ForEach(timers.timers) { TimerCard(timer: $0) }
                        }
                    }
                }
                .padding(28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Timers")
            .toolbar {
                Button { showingNew = true } label: { Label("New timer", systemImage: "plus") }
            }
            .sheet(isPresented: $showingNew) { NewTimerSheet() }
        }
    }
}

struct TimerCard: View {
    @Environment(TimerStore.self) private var timers
    let timer: KitchenTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let remaining = timer.remaining(at: ctx.date)
            VStack(spacing: 16) {
                HStack {
                    Text(timer.label).font(.title3.bold()).lineLimit(1)
                    Spacer()
                    Button(role: .destructive) { timers.remove(timer.id) } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                ZStack {
                    Circle().stroke(Color(.tertiarySystemFill), lineWidth: 16)
                    Circle()
                        .trim(from: 0, to: max(0.001, 1 - timer.progress(at: ctx.date)))
                        .stroke(timer.isFinished ? Color.red : Color.accentColor, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: remaining)
                    VStack(spacing: 4) {
                        Text(timer.isFinished ? "Done" : remaining.clockText)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if !timer.isRunning && !timer.isFinished {
                            Text("Paused").font(.headline).foregroundStyle(.secondary)
                        } else if let end = timer.endDate {
                            Text("Ends \(end.formatted(date: .omitted, time: .shortened))")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(height: 220)
                HStack(spacing: 12) {
                    Button { timers.add(60, to: timer.id) } label: { Text("+1 min").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                    if timer.isFinished {
                        Button { timers.restart(timer.id) } label: { Label("Restart", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                    } else if timer.isRunning {
                        Button { timers.pause(timer.id) } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button { timers.resume(timer.id) } label: { Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)
            }
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

/// One-line timer used on the Home screen.
struct CompactTimerRow: View {
    @Environment(TimerStore.self) private var timers
    let timer: KitchenTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color(.tertiarySystemFill), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: max(0.001, 1 - timer.progress(at: ctx.date)))
                        .stroke(timer.isFinished ? Color.red : Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading) {
                    Text(timer.label).font(.headline).lineLimit(1)
                    if !timer.isRunning && !timer.isFinished { Text("Paused").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(timer.isFinished ? "Done" : timer.remaining(at: ctx.date).clockText)
                    .font(.system(.title, design: .rounded).bold())
                    .monospacedDigit()
                Button {
                    timer.isRunning ? timers.pause(timer.id) : timers.resume(timer.id)
                } label: {
                    Image(systemName: timer.isRunning ? "pause.circle.fill" : "play.circle.fill").font(.title)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(timer.isFinished)
                Button { timers.remove(timer.id) } label: {
                    Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct NewTimerSheet: View {
    @Environment(TimerStore.self) private var timers
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var hours = 0
    @State private var minutes = 10
    @State private var seconds = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Roast potatoes", text: $label)
                }
                Section("Duration") {
                    HStack(spacing: 0) {
                        wheel("hr", value: $hours, range: 0..<13)
                        wheel("min", value: $minutes, range: 0..<60)
                        wheel("sec", value: $seconds, range: 0..<60)
                    }
                    .frame(height: 180)
                }
            }
            .navigationTitle("New timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        timers.start(label: label, seconds: TimeInterval(hours * 3600 + minutes * 60 + seconds))
                        dismiss()
                    }
                    .disabled(hours + minutes + seconds == 0)
                }
            }
        }
    }

    private func wheel(_ unit: String, value: Binding<Int>, range: Range<Int>) -> some View {
        Picker(unit, selection: value) {
            ForEach(range, id: \.self) { Text("\($0) \(unit)").tag($0) }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
