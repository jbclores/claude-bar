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
                        ("The cat", "The cat that matters right now: one that needs you, else one working, else one asleep."),
                        ("5h · 7d", "How much of your Claude usage limits you've used, and when each resets."),
                        ("Hover the cat", "A peek at the office. Click the cat for the full dropdown."),
                    ])
                    section("Office", [
                        ("Floors", "Each floor is one of your projects, laid out like your Cat Office. Idle cats sleep in the Lounge (1)."),
                        ("Floor menu · ▲▼ · strip", "Pick a floor. Strip colours: green working, amber needs you, grey empty."),
                        ("Follow", "Shows where things are happening. On each time the dropdown opens; picking a floor turns it off."),
                        ("Rings and \"!\"", "Green working, amber or \"!\" needs you, grey asleep. Hover a cat for its details."),
                    ])
                    section("Mouse tips", [
                        ("Zoom", "Double-click the room, or ⌘-scroll. Drag to look around; click \"1×\" for the whole room."),
                        ("Pat a cat", "Click a cat to hear it meow."),
                        ("🎵", "Lofi music while the office is open. Click to turn it off or on."),
                    ])
                    section("Projects and Settings", [
                        ("Projects", "Your projects' branch, model, context and status."),
                        ("Settings", "Launch at login, notifications, starting Cat Office, the hover peek, and the sounds."),
                    ])
                    section("If something's wrong", [
                        ("\"Cat Office isn't running\"", "Click Start in the office, or open your Cat Office folder and run npm run dev."),
                        ("No usage numbers", "Claude Code's status line hook isn't installed: see the full guide."),
                        ("A cat on the wrong floor", "Floors come from Cat Office: wait a minute, or reopen the dropdown."),
                        ("No sound", "Check Settings → Sounds and the volume; Focus mutes the finished purr."),
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
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.0).font(.callout.weight(.medium))
                    Text(item.1).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
