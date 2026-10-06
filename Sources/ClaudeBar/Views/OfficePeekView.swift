import AppKit
import ClaudeBarCore
import SwiftUI

/// Where the pointer is inside the peek, fed by PeekContainerView (AppKit tracking works while ClaudeBar
/// isn't the active app; SwiftUI's onHover doesn't reliably).
@MainActor
final class PeekPointer: ObservableObject {
    @Published var location: CGPoint?
}

private struct CatFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct OfficePeekView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var pointer: PeekPointer
    @State private var catFrames: [String: CGRect] = [:]

    static let size = CGSize(width: 500, height: 236)

    private var hovered: OfficeAgent? {
        guard let point = pointer.location, let office = state.office else { return nil }
        guard let id = catFrames.first(where: { $0.value.contains(point) })?.key else { return nil }
        return office.agents.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x2B2622).opacity(0.85))
                if let office = state.office {
                    room(PeekLayout.make(office.agents))
                } else {
                    offline
                }
                if let agent = hovered { CatCard(agent: agent, since: state.statusSince[agent.key]).padding(6) }
            }
            .frame(height: 158)
            HStack {
                Spacer()
                if state.office != nil {
                    Button("Open Cat Office ↗") { state.openCatOffice() }.buttonStyle(.link).font(.caption)
                }
            }
        }
        .padding(12)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .coordinateSpace(name: "peek")
        .onPreferenceChange(CatFramesKey.self) { catFrames = $0 }
    }

    @ViewBuilder private var header: some View {
        if let office = state.office {
            let count = office.agents.filter { $0.status != .ended }.count
            HStack(spacing: 4) {
                Text("Cat Office").font(.headline)
                Text("· \(count) cat\(count == 1 ? "" : "s") ·").foregroundStyle(.secondary)
                Text(office.claudeHindered ? "Claude hindered" : "Claude OK")
                    .foregroundStyle(office.claudeHindered ? Theme.waiting : .secondary)
            }
            .font(.callout)
        } else {
            Text("Cat Office").font(.headline)
        }
    }

    private func room(_ layout: PeekLayout) -> some View {
        HStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 2) {
                if layout.desks.isEmpty {
                    Text("Nobody at a desk").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(layout.desks) { agent in CatView(agent: agent, atDesk: true).catFrame(agent.id) }
                if layout.deskOverflow > 0 {
                    Text("+\(layout.deskOverflow) more").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 10)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1).padding(.vertical, 12)
            VStack(spacing: 2) {
                Text("lounge").font(.caption2).foregroundStyle(.secondary).padding(.top, 8)
                Spacer()
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(layout.lounge) { agent in CatView(agent: agent, atDesk: false, width: 50).catFrame(agent.id) }
                }
                if layout.loungeOverflow > 0 {
                    Text("+\(layout.loungeOverflow)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 172)
            .padding(.bottom, 10)
        }
    }

    private var offline: some View {
        VStack(spacing: 6) {
            Spacer()
            if let cat = state.catIds.first {
                SpriteImage(key: "\(cat)-sleeping") { await state.art.catImage(cat: cat, pose: .sleeping) }
                    .frame(width: 70, height: 74)
                    .opacity(0.8)
            }
            Text("Cat Office isn't running").font(.callout).foregroundStyle(.secondary)
            OfficeStarter(launch: state.officeLaunch, start: { state.startCatOffice() }, openLog: { state.openLauncherLog() })
            Spacer()
        }
    }
}

private extension View {
    func catFrame(_ id: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: CatFramesKey.self, value: [id: proxy.frame(in: .named("peek"))])
        })
    }
}

/// One cat in its pose, with the status ring at its feet, a desk when seated, and a "!" bubble when waiting.
struct CatView: View {
    let agent: OfficeAgent
    let atDesk: Bool
    var width: CGFloat = 64
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let cat = CatPicker.cat(for: agent, catIds: state.catIds)
        let pose = CatPose(status: agent.status)
        VStack(spacing: 1) {
            ZStack(alignment: .bottom) {
                StatusRing(status: agent.status, attention: false).scaleEffect(width / 64).offset(y: 3)
                if atDesk && agent.status == .working {
                    desk.offset(y: -14)
                    animatedCat(cat, pose).offset(y: 2)
                } else if atDesk {
                    desk.offset(x: -8, y: -10)
                    animatedCat(cat, pose).offset(x: 10, y: 2)
                } else {
                    animatedCat(cat, pose)
                }
                if agent.status == .waiting {
                    Text("!").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 16, height: 16).background(Circle().fill(Color(hex: 0xE5484D)))
                        .offset(x: 18, y: -60)
                }
            }
            .frame(width: width, height: width * 1.34)
            Text(agent.name).font(.system(size: 9)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).frame(width: width)
        }
    }

    private var desk: some View {
        SpriteImage(key: "desk") { await state.art.deskImage() }.frame(width: 60, height: 53)
    }

    private func animatedCat(_ cat: String, _ pose: CatPose) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || agent.status == .waiting)) { context in
            let motion = reduceMotion ? CatMotion(offsetY: 0, scale: 1)
                : CatMotion.at(status: agent.status, time: context.date.timeIntervalSinceReferenceDate)
            SpriteImage(key: "\(cat)-\(pose.rawValue)") { await state.art.catImage(cat: cat, pose: pose) }
                .frame(width: width * 0.875, height: width * 0.92)
                .scaleEffect(motion.scale, anchor: .bottom)
                .offset(y: motion.offsetY)
        }
    }
}

struct StatusRing: View {
    let status: AgentStatus
    let attention: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = Theme.color(status)
        switch status {
        case .working:
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { context in
                let pulse = reduceMotion ? 0.5 : 0.4 + 0.25 * sin(context.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.6)
                Ellipse().fill(color.opacity(pulse)).frame(width: 40, height: 10)
            }
        case .waiting:
            Ellipse().stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).frame(width: 40, height: 10)
        case .idle, .ended:
            Ellipse().fill(color.opacity(0.3)).frame(width: 40, height: 10)
        }
    }
}

/// An image loaded once from the art cache, keyed so the same sprite isn't reloaded.
struct SpriteImage: View {
    let key: String
    let load: () async -> Data?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .task(id: key) {
            if let data = await load() { image = NSImage(data: data) }
        }
    }
}

struct CatCard: View {
    let agent: OfficeAgent
    let since: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(Theme.color(agent.status)).frame(width: 7, height: 7)
                Text(agent.name).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(statusText).font(.caption).foregroundStyle(Theme.color(agent.status))
            }
            let place = [agent.repoName ?? (agent.cwd as NSString).lastPathComponent, agent.branch, agent.model]
                .compactMap { $0 }.filter { !$0.isEmpty }
            if !place.isEmpty {
                Text(place.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if let reason = agent.waitReason { Text(reason).font(.caption).foregroundStyle(Theme.waiting) }
            if let detail = agent.task ?? agent.lastAction { Text(detail).font(.caption).lineLimit(2) }
        }
        .padding(8)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusText: String {
        let start = agent.status == .waiting ? (agent.waitingSince ?? since) : since
        guard let start else { return agent.status.rawValue }
        return "\(agent.status.rawValue) \(Format.duration(Date().timeIntervalSince(start)))"
    }
}
