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

/// "5 cats · Claude OK" (or hindered), for the peek and the Office tab.
struct OfficeSummary: View {
    let office: OfficeSnapshot

    var body: some View {
        let count = office.agents.filter { $0.status != .ended }.count
        HStack(spacing: 4) {
            Text("\(count) cat\(count == 1 ? "" : "s") ·").foregroundStyle(.secondary)
            Text(office.claudeHindered ? "Claude hindered" : "Claude OK")
                .foregroundStyle(office.claudeHindered ? Theme.waiting : .secondary)
        }
    }
}

/// The tiny office: busy cats at desks, idle ones in the lounge, a card for the cat under the pointer; a sleeping
/// cat and the Start button while Cat Office is offline. Cat frames are measured in the "office" coordinate space,
/// which the parent sets up together with the PeekPointer it feeds.
struct OfficeRoomView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var pointer: PeekPointer
    @Environment(\.colorScheme) private var colorScheme
    @State private var catFrames: [String: CGRect] = [:]

    static let height: CGFloat = 180

    private var hovered: OfficeAgent? {
        guard let point = pointer.location, let office = state.office else { return nil }
        guard let id = catFrames.first(where: { $0.value.contains(point) })?.key else { return nil }
        return office.agents.first { $0.id == id }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .topLeading) {
                RoomBackdrop()
                if let office = state.office {
                    room(PeekLayout.make(office.agents))
                } else {
                    offline
                }
            }
            // Evening in dark mode: a soft night tint so the room doesn't glare in a dark menu.
            .overlay(Color(red: 0.05, green: 0.07, blue: 0.15).opacity(colorScheme == .dark ? 0.32 : 0).allowsHitTesting(false))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            if let agent = hovered { CatCard(agent: agent, since: state.statusSince[agent.key]).padding(6) }
        }
        .frame(height: Self.height)
        // Clicks only inside the visible room: the backdrop and cats extend past it, and took the tabs' clicks.
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onPreferenceChange(CatFramesKey.self) { catFrames = $0 }
    }

    private func room(_ layout: PeekLayout) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(layout.desks) { agent in CatView(agent: agent, atDesk: true).catFrame(agent.id) }
                ForEach(0..<layout.freeDesks, id: \.self) { _ in FreeDesk() }
                if layout.deskOverflow > 0 {
                    RoomPill(text: "+\(layout.deskOverflow) more")
                }
            }
            .padding(.leading, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            Lounge(cats: layout.lounge, overflow: layout.loungeOverflow)
        }
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var offline: some View {
        VStack(spacing: 6) {
            Spacer()
            if let cat = state.catIds.first {
                SpriteImage(key: "\(cat)-sleeping", fallback: Theme.idle) { await state.art.catImage(cat: cat, pose: .sleeping) }
                    .frame(width: 70, height: 74)
            } else {
                Image(systemName: "cat.fill").font(.system(size: 34)).foregroundStyle(.secondary)
            }
            RoomPill(text: "Cat Office isn't running")
            OfficeStarter(launch: state.officeLaunch, start: { state.startCatOffice() }, openLog: { state.openLauncherLog() })
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.regularMaterial))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Cat Office's own room art: a plaster back wall over a birch floor, a plant and a lamp.
struct RoomBackdrop: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                roomArt("assets/room/walls/plaster.png", size: 512, mode: .fill).frame(height: 46).clipped()
                Rectangle().fill(Color(hex: 0x73503F)).frame(height: 3)
                roomArt("assets/room/floors/birch.png", size: 1024, mode: .tile).frame(maxHeight: .infinity)
            }
            .background(Color(hex: 0xEADBC8)) // until the art has loaded, or if it can't
            roomArt("assets/room/props/tall-plant.png", size: 160, mode: .fit).frame(height: 70).offset(x: 6, y: 12)
            roomArt("assets/room/props/floor-lamp.png", size: 160, mode: .fit).frame(height: 64)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 14).offset(y: 12)
        }
    }

    private func roomArt(_ path: String, size: Int, mode: SpriteImage.Mode) -> SpriteImage {
        SpriteImage(key: path, fallback: nil, mode: mode) { await state.art.image(path: path, maxPixelSize: size) }
    }
}

/// The lounge: a rug, a round sofa and a cat bed, with up to three sleeping cats on them.
struct Lounge: View {
    let cats: [OfficeAgent]
    let overflow: Int
    @EnvironmentObject var state: AppState

    /// Where the 1st to 5th cat sleep: the bed, the sofa (two), the rug, the bean bag.
    private static let spots: [CGSize] = [
        CGSize(width: -40, height: 10), CGSize(width: 18, height: -28), CGSize(width: 46, height: -28),
        CGSize(width: 20, height: 22), CGSize(width: -50, height: -30),
    ]

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                art("assets/room/rugs/round-cream.png", 512).frame(width: 150).scaleEffect(x: 1, y: 0.45)
                art("assets/room/props/sofa-round.png", 256).frame(width: 96).offset(x: 34, y: -26)
                art("assets/room/props/cat-bed-blue.png", 160).frame(width: 52).offset(x: -40, y: 14)
                art("assets/room/props/bean-bag-cream.png", 160).frame(width: 40).offset(x: -50, y: -24)
                ForEach(Array(cats.prefix(Self.spots.count).enumerated()), id: \.element.id) { i, agent in
                    CatView(agent: agent, atDesk: false, width: i == 0 ? 46 : 38, plain: true)
                        .catFrame(agent.id)
                        .offset(Self.spots[i])
                }
            }
            .frame(width: 166, height: 110)
            RoomPill(text: summary)
        }
        .frame(width: 170)
    }

    private var summary: String {
        let asleep = cats.count + overflow
        return asleep == 0 ? "lounge · empty" : "lounge · \(asleep) asleep"
    }

    private func art(_ path: String, _ size: Int) -> some View {
        SpriteImage(key: path, fallback: nil) { await state.art.image(path: path, maxPixelSize: size) }
    }
}

/// A desk whose cat is out in the lounge.
struct FreeDesk: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 1) {
            SpriteImage(key: "desk", fallback: nil) { await state.art.deskImage() }
                .frame(width: 60, height: 53)
                .opacity(0.75)
                .frame(width: 64, height: 64 * 1.34, alignment: .bottom)
                .padding(.bottom, 14)
            RoomPill(text: "free desk").opacity(0.6)
        }
    }
}

/// White text on a dark pill, readable on the light floor and the night tint alike.
struct RoomPill: View {
    let text: String
    var detail: String?
    var detailColor: Color = .secondary

    var body: some View {
        VStack(spacing: 0) {
            Text(text).font(.system(size: 9, weight: .semibold)).lineLimit(1).truncationMode(.tail)
            if let detail { Text(detail).font(.system(size: 8)).foregroundStyle(detailColor).lineLimit(1) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(.black.opacity(0.55)))
    }
}

/// The hover peek: title, the office, and a link to Cat Office.
struct OfficePeekView: View {
    @EnvironmentObject var state: AppState

    static let size = CGSize(width: 500, height: 258)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Cat Office").font(.headline)
                if let office = state.office { OfficeSummary(office: office).font(.callout) }
            }
            OfficeRoomView()
            HStack {
                Spacer()
                if state.office != nil {
                    Button("Open Cat Office ↗") { state.openCatOffice() }.buttonStyle(.link).font(.caption)
                }
            }
        }
        .padding(12)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .coordinateSpace(name: "office")
    }
}

private extension View {
    func catFrame(_ id: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: CatFramesKey.self, value: [id: proxy.frame(in: .named("office"))])
        })
    }
}

/// One cat in its pose, with the status ring at its feet, a desk when seated, and a "!" bubble when waiting.
struct CatView: View {
    let agent: OfficeAgent
    let atDesk: Bool
    var width: CGFloat = 64
    /// Just the cat (lounge): no status ring, no name.
    var plain = false
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let cat = CatPicker.cat(for: agent, catIds: state.catIds)
        let scene = DeskScene(agent)
        VStack(spacing: 1) {
            ZStack(alignment: .bottom) {
                if agent.status == .waiting && !plain {
                    // B's spotlight: a soft amber glow under a cat that needs you.
                    Ellipse()
                        .fill(RadialGradient(colors: [Theme.waiting.opacity(0.6), Theme.waiting.opacity(0)],
                                             center: .center, startRadius: 3, endRadius: 46))
                        .frame(width: 96, height: 30)
                        .offset(y: 10)
                }
                if !plain { StatusRing(status: agent.status, attention: false).scaleEffect(width / 64).offset(y: 3) }
                if atDesk && scene.rear {
                    // A turned desk: the cat works on the far side, facing us, behind the desk.
                    animatedCat(cat, scene).offset(y: -12)
                    desk(scene).offset(y: -2)
                } else if atDesk && agent.status == .working {
                    desk(scene).offset(y: -14)
                    animatedCat(cat, scene).offset(y: 2)
                } else if atDesk {
                    // Waiting: up beside the desk, on the open side.
                    desk(scene).offset(x: scene.mirrored ? 8 : -8, y: -10)
                    animatedCat(cat, scene).offset(x: scene.mirrored ? -10 : 10, y: 2)
                } else {
                    animatedCat(cat, scene)
                }
                if agent.status == .waiting {
                    Text("!").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 16, height: 16).background(Circle().fill(Color(hex: 0xE5484D)))
                        .offset(x: 18, y: -60)
                }
            }
            .frame(width: width, height: plain ? width * 0.95 : width * 1.34)
            if !plain {
                let needsYou = agent.status == .waiting || state.attention.contains(agent.key)
                RoomPill(text: agent.label,
                         detail: Format.statusText(agent.status, needsYou: needsYou,
                                                   since: agent.waitingSince ?? state.statusSince[agent.key]),
                         detailColor: needsYou ? Theme.waiting : Theme.color(agent.status))
                    .frame(maxWidth: 84)
            }
        }
    }

    /// The cat's own desk in Cat Office (design, rear view, mirrored), else the default one.
    private func desk(_ scene: DeskScene) -> some View {
        SpriteImage(key: "desk-\(scene.deskId ?? "default")-\(scene.rear)", fallback: nil) {
            await state.art.deskImage(id: scene.deskId, rear: scene.rear)
        }
        .frame(width: 60, height: 53)
        .scaleEffect(x: scene.mirrored ? -1 : 1, y: 1)
    }

    private func animatedCat(_ cat: String, _ scene: DeskScene) -> some View {
        let pose = scene.pose
        let direction = scene.direction
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || agent.status == .waiting)) { context in
            let motion = reduceMotion ? CatMotion(offsetY: 0, scale: 1)
                : CatMotion.at(status: agent.status, time: context.date.timeIntervalSinceReferenceDate)
            SpriteImage(key: "\(cat)-\(pose.rawValue)-\(direction)", fallback: Theme.color(agent.status)) {
                await state.art.catImage(cat: cat, pose: pose, direction: direction)
            }
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

/// An image loaded once from the art cache, keyed so the same sprite isn't reloaded. When it can't be loaded,
/// a plain circle in `fallback` stands in (nothing for nil); it's tried again the next time the peek opens.
struct SpriteImage: View {
    enum Mode { case fit, fill, tile }

    let key: String
    let fallback: Color?
    var mode: Mode = .fit
    let load: () async -> Data?
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                switch mode {
                case .fit: Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                case .fill: Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                case .tile: Image(nsImage: image).resizable(resizingMode: .tile)
                }
            } else if failed, let fallback {
                Circle().fill(fallback.opacity(0.8)).frame(width: 22, height: 22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            } else {
                Color.clear
            }
        }
        .task(id: key) {
            if let data = await load(), let loaded = NSImage(data: data) {
                // Tiles repeat at Retina scale (2 pixels per point), like Cat Office draws its floors.
                if mode == .tile, let rep = loaded.representations.first {
                    loaded.size = NSSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2)
                }
                image = loaded
            } else {
                failed = true
            }
        }
    }
}

struct CatCard: View {
    let agent: OfficeAgent
    let since: Date?
    @EnvironmentObject var state: AppState

    var body: some View {
        let needsYou = agent.status == .waiting || state.attention.contains(agent.key)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(needsYou ? Theme.waiting : Theme.color(agent.status)).frame(width: 7, height: 7)
                Text(agent.label).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(Format.statusText(agent.status, needsYou: needsYou, since: agent.waitingSince ?? since))
                    .font(.caption).foregroundStyle(needsYou ? Theme.waiting : Theme.color(agent.status))
            }
            let place = [agent.name, agent.repoName, agent.branch, agent.model.map(Format.modelName)]
                .compactMap { $0 }.filter { !$0.isEmpty }
            Text(place.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let reason = agent.waitReason { Text(reason).font(.caption).foregroundStyle(Theme.waiting) }
            if let task = agent.task, !task.isEmpty { Text(task).font(.caption).lineLimit(3) }
            if let last = agent.lastAction, !last.isEmpty {
                Text("Last: \(last)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(8)
        .frame(maxWidth: 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
