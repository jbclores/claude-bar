// Sources/ClaudeBar/Views/FloorPicker.swift
import ClaudeBarCore
import SwiftUI

/// "12 claude-bar · 3 cats ⌃⌄" menu, ▲ / ▼, Follow, and a strip with one bar per floor.
struct FloorPicker: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var floors: FloorSelection

    var body: some View {
        let shown = floors.shown(state)
        let agents = state.office?.agents ?? []
        let activity = FloorPlan.activity(of: state.building, agents: agents, attention: state.attention)
        let ids = state.building.floors.map(\.id)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(state.building.floors) { f in
                        let count = FloorPlan.cats(on: f.id, agents: agents, in: state.building).count
                        Button { floors.choice.pick(f.id) } label: {
                            Text("\(activity[f.id] == .needsYou ? "● " : "")\(f.id) \(f.name)\(count > 0 ? " · \(count)" : "")")
                        }
                    }
                } label: {
                    // One Text: a borderless menu draws only the first view of its label.
                    let count = FloorPlan.cats(on: shown, agents: agents, in: state.building).count
                    Text("\(shown) \(state.building.floor(id: shown)?.name ?? "Lounge") · \(count) cat\(count == 1 ? "" : "s")")
                        .font(.callout.weight(.semibold)).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button { floors.choice.step(1, from: shown, floors: ids) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless).help("Up a floor").target("floor-up", in: floors)
                Button { floors.choice.step(-1, from: shown, floors: ids) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless).help("Down a floor").target("floor-down", in: floors)
                Spacer()
                Button { floors.choice.resumeFollow() } label: {
                    Label("Follow", systemImage: "scope").font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(floors.choice.follow ? Theme.working.opacity(0.25) : Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .target("floor-follow", in: floors)
                .help(floors.choice.follow ? "Following where things happen" : "Follow where things happen")
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

    private func color(_ a: FloorActivity) -> Color {
        switch a {
        case .needsYou: Theme.waiting
        case .working: Theme.working
        case .idle: Theme.idle.opacity(0.5)
        case .empty: Color.primary.opacity(0.12)
        }
    }
}

private extension View {
    /// Records this button's frame in the window, for the click test.
    func target(_ name: String, in floors: FloorSelection) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { floors.targets[name] = $0 }
    }
}
