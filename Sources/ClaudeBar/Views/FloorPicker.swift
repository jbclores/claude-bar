import AppKit
// Sources/ClaudeBar/Views/FloorPicker.swift
import ClaudeBarCore
import SwiftUI

/// "12 claude-bar · 3 cats ⌃⌄" menu, music, Follow, and a strip with one bar per floor (click one to go there).
struct FloorPicker: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var floors: FloorSelection
    /// The music + Follow group's width, to fit the floor menu into the rest of the row.
    @State private var controlsWidth: CGFloat = 0

    var body: some View {
        let shown = floors.shown(state)
        let agents = state.office?.agents ?? []
        let activity = FloorPlan.activity(of: state.building, agents: agents, attention: state.attention, mirror: state.mirror)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(state.building.menuOrder) { f in
                        let count = FloorPlan.cats(on: f.id, agents: agents, in: state.building, mirror: state.mirror).count
                        Button { floors.choice.pick(f.id) } label: {
                            Text("\(activity[f.id] == .needsYou ? "● " : "")\(f.id) \(f.name)\(count > 0 ? " · \(count)" : "")")
                        }
                    }
                } label: {
                    // One Text: a borderless menu draws only the first view of its label. A long floor name is cut
                    // with "…", keeping the floor number and the cat count.
                    let count = FloorPlan.cats(on: shown, agents: agents, in: state.building, mirror: state.mirror).count
                    Text(FitText.label(prefix: "\(shown) ", name: state.building.floor(id: shown)?.name ?? "Lounge",
                                       suffix: " · \(count) cat\(count == 1 ? "" : "s")",
                                       width: Double(max(60, DropdownLayout.contentWidth - 8 - controlsWidth - Self.menuChrome)), measure: Self.measure))
                        .font(.callout.weight(.semibold)).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                // (the row is the dropdown's fixed content width: it grows to fit its content, so it can't be measured)
                Spacer(minLength: 8)
                // Music and Follow on the right, so the floor menu has the rest of the row; the strip and the menu
                // pick floors, so there are no ▲▼.
                HStack(spacing: 8) {
                    MusicButton()
                    Button { floors.choice.resumeFollow() } label: {
                        Label("Follow", systemImage: "scope").font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(floors.choice.follow ? Theme.working.opacity(0.25) : Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .target("floor-follow", in: floors)
                    .help(floors.choice.follow ? "Following where things happen" : "Follow where things happen")
                }
                .fixedSize()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { controlsWidth = $0 }
            }
            HStack(spacing: 3) {
                ForEach(state.building.floors) { f in
                    Capsule()
                        .fill(f.id == shown ? Color.primary.opacity(0.6) : color(activity[f.id] ?? .empty))
                        .frame(height: 4)
                        .frame(maxWidth: 30)
                        .contentShape(Rectangle().inset(by: -4))
                        .onTapGesture { floors.choice.pick(f.id) }
                        .help(Self.stripHelp(f, activity: activity[f.id] ?? .empty, shown: f.id == shown))
                        .accessibilityElement()
                        .accessibilityLabel(Self.stripHelp(f, activity: activity[f.id] ?? .empty, shown: f.id == shown))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { floors.choice.pick(f.id) }
                }
            }
        }
        // A picked floor deleted from Cat Office: back to Follow.
        .onChange(of: state.building) { _, b in floors.choice.reconcile(floors: b.floors.map(\.id)) }
    }

    /// A strip bar's tooltip, saying what its color means: "6 Desk pool: a cat needs you".
    static func stripHelp(_ f: Floor, activity: FloorActivity, shown: Bool) -> String {
        let what = switch activity {
        case .needsYou: "a cat needs you"
        case .working: "cats running"
        case .idle: "cats idle"
        case .empty: "no cats"
        }
        return "\(f.id) \(f.name): \(what)\(shown ? " (showing)" : "")"
    }

    /// The menu's ⌄ and padding, next to its label.
    static let menuChrome: CGFloat = 44
    /// The label's width in the menu's font (callout, semibold).
    static func measure(_ text: String) -> Double {
        let font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize, weight: .semibold)
        return Double((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private func color(_ a: FloorActivity) -> Color {
        switch a {
        case .needsYou: Theme.waiting
        case .working: Theme.working
        case .idle: Theme.idle.opacity(0.5)
        case .empty: Color.primary.opacity(0.12)
        }
    }
}

extension View {
    /// Records this button's frame in the window, for the click tests.
    func target(_ name: String, in floors: FloorSelection) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { floors.targets[name] = $0 }
    }
}
