import SwiftUI

/// The ❓ panel: what ClaudeBar shows, mouse tips, and fixes for common problems; "Full guide ↗" opens the guide
/// that ships inside the app (Resources/Help/guide.html).
struct HelpPanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ClaudeBar help").font(.headline)
                Spacer()
                Button("Full guide ↗") { state.openHelpGuide() }.buttonStyle(.link).font(.callout)
            }
            .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    section("The menu bar", [
                        ("The cat", "The cat that matters right now: one that needs you, else one running, else one asleep."),
                        ("5h · 7d", "How much of your Claude usage limits you've used, and when each resets."),
                        ("Hover the cat", "A peek at the office. Click the cat (or press ⌃⌥C) for the full dropdown."),
                    ])
                    section("Usage", [
                        ("The line under the bars", "Where your pace leads. Amber when you'd reach a limit within the hour; ClaudeBar warns you once."),
                        ("The small graph", "Your last 5 hours of use, next to the 5h bar."),
                        ("Click the usage area", "The last 7 days: each day's highest 5-hour use, and when a limit was reached."),
                    ])
                    section("Office", [
                        ("Floors", "Each floor is one of your projects, laid out like your Cat Office. Idle cats sleep in the Lounge (1)."),
                        ("Floor menu · ▲▼ · strip", "Pick a floor. Strip colours: green running, amber needs you, grey empty."),
                        ("Follow", "Shows where things are happening. On each time the dropdown opens; picking a floor turns it off."),
                        ("Rings and \"!\"", "Green running, amber or \"!\" needs you, grey asleep. Hover a cat for its details."),
                        ("A cat's card", "Open in Cat Office (its panel), and Show terminal for Terminal and iTerm sessions."),
                        ("Needs you", "Its question shows in the card and under the office. Sessions in Orca can be answered right there."),
                    ])
                    section("Mouse tips", [
                        ("Zoom", "Double-click the room, or ⌘-scroll. Drag to look around; click \"1×\" for the whole room."),
                        ("Pat a cat", "Click a cat to hear it meow."),
                        ("Talk", "Hold ⌃⌥V and say allow, deny, what's running, how's my usage, or what did I do today."),
                        ("🎵", "Lofi music while the office is open. Click to turn it off or on."),
                    ])
                    section("Projects and Settings", [
                        ("Projects", "Today's recap, then your projects' branch, model, context and status."),
                        ("Settings", "General (login, shortcut), Alerts (notifications, quiet hours) and Office (Cat Office, sounds). Setup & more holds the rest."),
                        ("Quiet hours", "No sounds or notifications in the hours you pick, or for an hour. A 🔕 shows next to Usage."),
                    ])
                    section("If something's wrong", [
                        ("First time?", "Settings → Set up ClaudeBar…"),
                        ("\"Cat Office isn't running\"", "Click Start in the office, or open your Cat Office folder and run npm run dev."),
                        ("No usage numbers", "Turn on usage in Settings → Set up ClaudeBar…, then send a message in Claude Code."),
                        ("A cat on the wrong floor", "Floors come from Cat Office: wait a minute, or reopen the dropdown."),
                        ("No sound", "Check Settings → Cat sounds, Choose sounds and the volume, and quiet hours; Focus mutes the finished purr."),
                        ("\"Two copies of Cat Office\"", "Each runs its own office, so cats may not match: click Stop the extra one."),
                        ("Show terminal does nothing", "Let ClaudeBar control Terminal / iTerm: System Settings → Privacy & Security → Automation."),
                    ])
                }
                .padding(.trailing, 6)
            }
        }
        .padding(14)
        .frame(width: 340, height: 380)
    }

    private func section(_ title: String, _ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.0).font(.callout.weight(.medium))
                    Text(item.1).font(.caption).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Where the ❓ button is (window points from the top-left), so the click test hits exactly it.
@MainActor
enum HelpButton {
    static var frame: CGRect = .zero
}
