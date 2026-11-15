import Foundation
import Observation
import UserNotifications
import AVFoundation

struct KitchenTimer: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String
    var duration: TimeInterval
    /// Set while running.
    var endDate: Date?
    /// Set while paused.
    var pausedRemaining: TimeInterval?
    var finishedAt: Date?

    var isRunning: Bool { endDate != nil }
    var isFinished: Bool { finishedAt != nil }

    func remaining(at now: Date = Date()) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(now)) }
        return pausedRemaining ?? duration
    }

    func progress(at now: Date = Date()) -> Double {
        guard duration > 0 else { return 1 }
        return 1 - remaining(at: now) / duration
    }
}

extension TimeInterval {
    /// 3725 -> "1:02:05", 125 -> "2:05"
    var clockText: String {
        let s = Int(self.rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

@Observable
@MainActor
final class TimerStore {
    private(set) var timers: [KitchenTimer] = [] { didSet { save() } }
    var ringing: [KitchenTimer] { timers.filter(\.isFinished) }

    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private let alarm = AlarmSound()
    @ObservationIgnored private let storageKey = "kitchen.timers.v1"

    init() {
        load()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    // MARK: - Actions

    @discardableResult
    func start(label: String, seconds: TimeInterval) -> KitchenTimer {
        let t = KitchenTimer(label: label.isEmpty ? "Timer" : label, duration: seconds, endDate: Date().addingTimeInterval(seconds))
        timers.append(t)
        schedule(t)
        return t
    }

    func pause(_ id: UUID) {
        guard let i = index(id), let end = timers[i].endDate else { return }
        timers[i].pausedRemaining = max(0, end.timeIntervalSinceNow)
        timers[i].endDate = nil
        unschedule(id)
    }

    func resume(_ id: UUID) {
        guard let i = index(id), timers[i].endDate == nil, !timers[i].isFinished else { return }
        let remaining = timers[i].pausedRemaining ?? timers[i].duration
        timers[i].endDate = Date().addingTimeInterval(remaining)
        timers[i].pausedRemaining = nil
        schedule(timers[i])
    }

    func add(_ seconds: TimeInterval, to id: UUID) {
        guard let i = index(id) else { return }
        if timers[i].isFinished {
            timers[i].finishedAt = nil
            timers[i].endDate = Date().addingTimeInterval(seconds)
            timers[i].duration = seconds
        } else if let end = timers[i].endDate {
            timers[i].endDate = end.addingTimeInterval(seconds)
            timers[i].duration += seconds
        } else {
            timers[i].pausedRemaining = (timers[i].pausedRemaining ?? timers[i].duration) + seconds
            timers[i].duration += seconds
        }
        if timers[i].isRunning { schedule(timers[i]) }
        updateAlarm()
    }

    func restart(_ id: UUID) {
        guard let i = index(id) else { return }
        timers[i].finishedAt = nil
        timers[i].pausedRemaining = nil
        timers[i].endDate = Date().addingTimeInterval(timers[i].duration)
        schedule(timers[i])
        updateAlarm()
    }

    func remove(_ id: UUID) {
        unschedule(id)
        timers.removeAll { $0.id == id }
        updateAlarm()
    }

    func dismissAllRinging() {
        for t in ringing { unschedule(t.id) }
        timers.removeAll(where: \.isFinished)
        updateAlarm()
    }

    // MARK: - Ticking

    private func tick() {
        let now = Date()
        var changed = false
        var updated = timers
        for i in updated.indices {
            if let end = updated[i].endDate, end <= now {
                updated[i].endDate = nil
                updated[i].finishedAt = now
                changed = true
            }
        }
        if changed { timers = updated }
        updateAlarm()
    }

    private func updateAlarm() {
        if ringing.isEmpty { alarm.stop() } else { alarm.start() }
    }

    private func index(_ id: UUID) -> Int? { timers.firstIndex { $0.id == id } }

    // MARK: - Notifications (cover the case where the app isn't on screen)

    private func schedule(_ t: KitchenTimer) {
        guard let end = t.endDate else { return }
        let content = UNMutableNotificationContent()
        content.title = "⏰ \(t.label)"
        content.body = "Your \(t.duration.clockText) timer is done."
        content.sound = .default
        let interval = max(1, end.timeIntervalSinceNow)
        let request = UNNotificationRequest(identifier: t.id.uuidString, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }

    private func unschedule(_ id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }

    // MARK: - Persistence (timers survive the app being closed)

    private func save() {
        if let data = try? JSONEncoder().encode(timers) { UserDefaults.standard.set(data, forKey: storageKey) }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([KitchenTimer].self, from: data) else { return }
        timers = saved
    }
}

/// A repeating two-tone chime, generated in code so no audio files are needed. Uses the
/// .playback session so it is loud and isn't silenced by the mute setting.
@MainActor
final class AlarmSound {
    private var player: AVAudioPlayer?

    func start() {
        guard player?.isPlaying != true else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(data: Self.chimeWAV)
            p.numberOfLoops = -1
            p.volume = 1
            p.play()
            player = p
        } catch {
            print("Alarm sound failed: \(error)")
        }
    }

    func stop() {
        guard player != nil else { return }
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// ~1.6 s loop: two short bell-like notes, then silence.
    private static let chimeWAV: Data = {
        let rate = 44_100
        let notes: [(freq: Double, start: Double, length: Double)] = [(880, 0, 0.35), (1318.5, 0.4, 0.5)]
        let total = Int(1.6 * Double(rate))
        var samples = [Int16](repeating: 0, count: total)
        for note in notes {
            let s0 = Int(note.start * Double(rate)), n = Int(note.length * Double(rate))
            for i in 0..<n where s0 + i < total {
                let t = Double(i) / Double(rate)
                let env = exp(-t * 6) * min(1, t * 200)
                let v = (sin(2 * .pi * note.freq * t) + 0.3 * sin(4 * .pi * note.freq * t)) * env * 0.6
                samples[s0 + i] = Int16(max(-1, min(1, v)) * Double(Int16.max))
            }
        }
        var data = Data()
        func append<T>(_ v: T) { withUnsafeBytes(of: v) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(total * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + byteCount).littleEndian)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian); append(UInt16(1).littleEndian)
        append(UInt32(rate).littleEndian); append(UInt32(rate * 2).littleEndian)
        append(UInt16(2).littleEndian); append(UInt16(16).littleEndian)
        data.append(contentsOf: Array("data".utf8)); append(byteCount.littleEndian)
        samples.forEach { append($0.littleEndian) }
        return data
    }()
}
