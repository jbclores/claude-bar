import ClaudeBarCore
import SwiftUI

/// The quiet line under the usage bars: grey "On pace for about 55% …", amber when a limit comes before its reset.
struct UsageForecastLine: View {
    let forecast: UsageForecast

    var body: some View {
        Text(forecast.line(time: AppState.usageTime))
            .font(.caption)
            // Amber only when it's urgent: reached, or within the hour.
            .foregroundStyle(forecast.isUrgent(now: Date()) ? Theme.waitingText : Theme.secondaryText)
            .lineLimit(1)
    }
}

/// Today's 5-hour usage as a small step line, 0–100%, over the last 5 hours (left) to now (right).
struct UsageSparkline: View {
    let samples: [UsageSample]

    var body: some View {
        // In the bar's colour (green, amber when high), filled underneath so it reads as "your usage" at a glance.
        let color = Theme.color(UsageLevel(percent: samples.last?.fiveHourPct ?? 0))
        GeometryReader { geo in
            let line = Self.line(samples, in: geo.size)
            ZStack {
                if let first = line.first, let last = line.last {
                    Path { p in
                        p.move(to: CGPoint(x: first.x, y: geo.size.height))
                        for point in line { p.addLine(to: point) }
                        p.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(color.opacity(0.28))
                    Path { p in
                        p.move(to: first)
                        for point in line.dropFirst() { p.addLine(to: point) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                }
            }
        }
        .frame(height: 16)
        .accessibilityLabel("Your last 5 hours of usage")
    }

    /// The step line's points: the last 5 hours (the 5-hour window's length; since midnight if shorter) left to now
    /// right, 0–100% bottom to top.
    static func line(_ samples: [UsageSample], in size: CGSize) -> [CGPoint] {
        let now = Date().timeIntervalSince1970
        var start = max(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970, now - 5 * 3600)
        // Begin at the first sample (keeping at least an hour), so the line starts at the left edge instead of
        // leaving a blank stretch after the percentage when the log is younger than the window.
        if let first = samples.first(where: { $0.fiveHourPct != nil })?.at.timeIntervalSince1970, first > start {
            start = min(first, now - 3600)
        }
        let span = max(3600, now - start)
        var points: [CGPoint] = []
        for s in samples {
            guard let pct = s.fiveHourPct else { continue }
            let x = size.width * CGFloat(max(0, s.at.timeIntervalSince1970 - start) / span)
            let y = size.height * CGFloat(1 - min(100, pct) / 100)
            if let l = points.last { points.append(CGPoint(x: x, y: l.y)) }
            points.append(CGPoint(x: x, y: y))
        }
        if let l = points.last { points.append(CGPoint(x: size.width * CGFloat((now - start) / span), y: l.y)) }
        return points
    }
}

/// The last 7 days: each day's highest 5-hour use, and when a limit was reached.
struct UsageWeekChart: View {
    let history: UsageHistory

    var body: some View {
        let now = Date(), cal = Calendar.current
        let days = history.dailyHighs(days: 7, now: now, calendar: cal)
        VStack(alignment: .leading, spacing: 6) {
            Text("Highest 5-hour use each day").font(.caption).foregroundStyle(Theme.secondaryText)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(days, id: \.day) { d in
                    VStack(spacing: 3) {
                        if let high = d.high {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(high >= 100 ? Theme.waiting : Theme.working)
                                .frame(width: 22, height: max(2, 48 * CGFloat(high / 100)))
                        } else {
                            // No use that day: a faint dash, so it reads as empty, not missing.
                            Capsule().fill(Theme.secondaryText.opacity(0.35)).frame(width: 10, height: 2)
                        }
                        Text(cal.isDateInToday(d.day) ? "Today" : d.day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption2).foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .help(d.high.map { "\(Int($0))%" } ?? "No use")
                }
            }
            .frame(height: 66, alignment: .bottom)
            ForEach(Array(history.limitHits(days: 7, now: now, calendar: cal).prefix(3).enumerated()), id: \.offset) { _, hit in
                Text("\(hit.window == .fiveHour ? "Limit" : "7-day limit") reached: \(AppState.usageTime(hit.at))")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}

/// Settings' shortcut box: shows the shortcut; click it and press a new one (Escape cancels); ✕ turns it off.
/// `talk` makes it the push-to-talk shortcut's box instead of the open shortcut's.
struct ShortcutField: View {
    @EnvironmentObject var state: AppState
    var talk = false
    @State private var recording = false
    @State private var monitor: Any?

    private var shortcut: Shortcut? { talk ? state.settings.voice.talkShortcut : state.settings.shortcut }

    private func set(_ shortcut: Shortcut?) {
        if talk { state.setTalkShortcut(shortcut) } else { state.setShortcut(shortcut) }
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Press keys…" : shortcut?.display ?? "Off")
                    .font(.callout).frame(minWidth: 56)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(recording ? 0.12 : 0.06)))
            }
            .buttonStyle(.plain)
            .help("Click, then press a new shortcut (Escape cancels)")
            .target(talk ? "talk-shortcut-field" : "shortcut-field", in: state.shortcutTargets)
            if shortcut != nil, !recording {
                Button { set(nil) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.secondaryText).help("Turn the shortcut off")
                    .accessibilityLabel("Turn the shortcut off")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        if talk { state.talkShortcutTaken = false } else { state.shortcutTaken = false }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Escape
            let f = event.modifierFlags
            if let s = Shortcut(keyCode: UInt32(event.keyCode), control: f.contains(.control), option: f.contains(.option),
                                shift: f.contains(.shift), command: f.contains(.command)) {
                set(s)
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Settings' quiet hours: the switch, from / to times, weekends, and "Quiet for 1 hour".
struct QuietHoursSettings: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let q = state.settings.quietHours
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { q.on }, set: { state.setQuietHours(on: $0) })) {
                Text("Quiet hours").frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .help("No sounds or notifications in these hours. The office keeps running, and the menu bar still shows who needs you.")
            if q.on {
                HStack(spacing: 8) {
                    Text("From").foregroundStyle(Theme.secondaryText)
                    time(q.from) { state.setQuietTime("from", minutes: $0) }
                    Text("to").foregroundStyle(Theme.secondaryText)
                    time(q.to) { state.setQuietTime("to", minutes: $0) }
                    Spacer()
                }
                .padding(.leading, 16)
                Toggle("All weekend too", isOn: Binding(get: { q.weekends }, set: { state.setQuietWeekends($0) }))
                    .toggleStyle(.checkbox).padding(.leading, 16)
            }
            if let until = state.quietUntil {
                HStack(spacing: 10) {
                    Text("Quiet until \(AppState.usageTime(until))").foregroundStyle(Theme.secondaryText)
                    Button("End now") { state.endQuietHour() }.buttonStyle(.link)
                }
                .font(.caption)
            } else {
                Button("Quiet for 1 hour") { state.quietForAnHour() }.buttonStyle(.link).font(.caption)
            }
        }
    }

    private func time(_ minutes: Int, set: @escaping (Int) -> Void) -> some View {
        let cal = Calendar.current
        let date = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return DatePicker("", selection: Binding(get: { date }, set: { d in
            let c = cal.dateComponents([.hour, .minute], from: d)
            set((c.hour ?? 0) * 60 + (c.minute ?? 0))
        }), displayedComponents: .hourAndMinute)
        .labelsHidden().datePickerStyle(.field).fixedSize()
    }
}
