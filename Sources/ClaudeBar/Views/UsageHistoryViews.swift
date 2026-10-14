import ClaudeBarCore
import SwiftUI

/// The quiet line under the usage bars: grey "On pace for about 55% …", amber when a limit comes before its reset.
struct UsageForecastLine: View {
    let forecast: UsageForecast

    var body: some View {
        Text(forecast.line(time: AppState.usageTime))
            .font(.caption)
            .foregroundStyle(forecast.atRisk ? Theme.waiting : Theme.secondaryText)
            .lineLimit(1)
    }
}

/// Today's 5-hour usage as a thin step line, 0–100%, from midnight (left) to now (right).
struct UsageSparkline: View {
    let samples: [UsageSample]

    var body: some View {
        GeometryReader { geo in
            let start = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
            let span = max(3600, Date().timeIntervalSince1970 - start)
            Path { p in
                var last: CGPoint?
                for s in samples {
                    guard let pct = s.fiveHourPct else { continue }
                    let x = geo.size.width * CGFloat((s.at.timeIntervalSince1970 - start) / span)
                    let y = geo.size.height * CGFloat(1 - min(100, pct) / 100)
                    if let l = last { p.addLine(to: CGPoint(x: x, y: l.y)); p.addLine(to: CGPoint(x: x, y: y)) } else { p.move(to: CGPoint(x: x, y: y)) }
                    last = CGPoint(x: x, y: y)
                }
                if let l = last { p.addLine(to: CGPoint(x: geo.size.width * CGFloat((Date().timeIntervalSince1970 - start) / span), y: l.y)) }
            }
            .stroke(Theme.working, lineWidth: 1.5)
        }
        .frame(height: 14)
        // A faint track along the bottom: today, midnight to now, so a short stretch of use reads as part of the day.
        .background(alignment: .bottom) { Capsule().fill(Color.primary.opacity(0.1)).frame(height: 2) }
        .accessibilityLabel("Today's 5-hour usage")
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
                        RoundedRectangle(cornerRadius: 2)
                            .fill((d.high ?? 0) >= 100 ? Theme.waiting : Theme.working)
                            .frame(width: 22, height: max(2, 48 * CGFloat((d.high ?? 0) / 100)))
                            .opacity(d.high == nil ? 0 : 1)
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
                    .font(.caption).foregroundStyle(Theme.waiting)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}
