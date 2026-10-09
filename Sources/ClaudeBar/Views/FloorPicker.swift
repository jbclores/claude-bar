import AppKit
// Sources/ClaudeBar/Views/FloorPicker.swift
import ClaudeBarCore
import SwiftUI

/// "12 claude-bar · 3 cats ⌃⌄" menu, ▲ / ▼, Follow, and a strip with one bar per floor.
struct FloorPicker: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var floors: FloorSelection
    /// The ▲▼ + Follow group's width, to fit the floor menu into the rest of the row.
    @State private var controlsWidth: CGFloat = 0

    var body: some View {
        let shown = floors.shown(state)
        let agents = state.office?.agents ?? []
        let activity = FloorPlan.activity(of: state.building, agents: agents, attention: state.attention, mirror: state.mirror)
        let ids = state.building.floors.map(\.id)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(state.building.floors) { f in
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
                // ▲▼ sit with Follow on the right, so the floor menu has the rest of the row.
                HStack(spacing: 8) {
                    Button { floors.choice.step(1, from: shown, floors: ids) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless).help("Up a floor").target("floor-up", in: floors)
                    Button { floors.choice.step(-1, from: shown, floors: ids) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless).help("Down a floor").target("floor-down", in: floors)
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
                        .help("\(f.id) · \(f.name)")
                }
            }
        }
        // A picked floor deleted from Cat Office: back to Follow.
        .onChange(of: state.building) { _, b in floors.choice.reconcile(floors: b.floors.map(\.id)) }
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
