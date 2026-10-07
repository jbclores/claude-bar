import AppKit
import ClaudeBarCore
import ImageIO
import SwiftUI

/// A floor drawn as Cat Office lays it out (BuiltRoom): one cached picture of the room, fitted by SceneFit, with the
/// live layer (cats, and the furniture in front of them) on top.
struct FloorScene: View {
    let room: BuiltRoom
    /// The same floor's simple room, shown until its picture exists (so a failed load never leaves it blank).
    let floor: Floor
    /// building.json catHeight (world px).
    let catHeight: Double
    /// Who's where; nil draws no cats (Cat Office offline).
    var cast: SceneCast?
    @EnvironmentObject var state: AppState
    @Environment(\.officeNight) private var night
    /// The last picture loaded for this floor, shown until the cache has the current one.
    @State private var loaded: (floorId: Int, image: NSImage)?

    /// Pixels per point of the room's picture (Retina).
    static let pixelsPerPoint: CGFloat = 2

    private struct LoadKey: Equatable {
        let room: BuiltRoom
        let night: Bool
        let scale: CGFloat
    }

    var body: some View {
        GeometryReader { proxy in
            let fit = SceneFit.fill(floor: room.frame, content: room.contentBounds(catHeight: catHeight),
                                    keep: room.catBounds(catHeight: catHeight), into: proxy.size)
            let scale = RoomImageCache.quantized(fit.scale * Self.pixelsPerPoint)
            let frame = fit.rect(RoomImageCache.imageBounds(room))
            let origin = proxy.frame(in: .named("roomContent")).origin
            ZStack(alignment: .topLeading) {
                if let image = RoomImageCache.shared.cached(room, night: night, scale: scale)
                    ?? (loaded?.floorId == room.floorId ? loaded?.image : nil) {
                    Image(nsImage: image).resizable().interpolation(.high)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                } else {
                    RoomBackdrop(floor: floor)
                }
                if let cast {
                    SceneCats(room: room, fit: fit, origin: origin, catHeight: catHeight, cast: cast)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .preference(key: SceneFitKey.self,
                        value: [room.floorId: SceneFit(scale: fit.scale, origin: CGPoint(x: origin.x + fit.origin.x, y: origin.y + fit.origin.y))])
            .task(id: LoadKey(room: room, night: night, scale: scale)) {
                if let image = await RoomImageCache.shared.image(for: room, night: night, scale: scale, art: state.art) {
                    loaded = (room.floorId, image)
                }
            }
        }
    }
}

/// Each shown floor's fit, by floor id, in "roomContent" points: for walks and rides from its real elevator.
struct SceneFitKey: PreferenceKey {
    static let defaultValue: [Int: SceneFit] = [:]
    static func reduce(value: inout [Int: SceneFit], nextValue: () -> [Int: SceneFit]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Who's on a built floor and where they sit (FloorPlan.seating over the floor's built desks and seats).
struct SceneCast: Equatable {
    var seating: FloorSeating
    var agents: [OfficeAgent]
    /// The desk id at each of `seating.desks`.
    var deskIds: [String]
    var lounge: Bool
}

/// One cat placed on a built floor, in world terms.
struct SceneCat {
    enum Kind { case desk, seat, helper, queue }
    let agent: OfficeAgent
    let kind: Kind
    let at: FloorPoint
    /// World px above its floor point.
    let lift: Double
    /// 1, or 0.8 for a helper beside its parent.
    let size: Double
    let pose: CatPose
    let direction: String
    let perch: String?
    /// The desk it works at (world px), for the screen's glow at night.
    let desk: CGRect?
}

extension SceneCast {
    /// Helpers stand beside their parent this far apart (floor u, v), at this size.
    static let helperStep = (u: 0.04, v: -0.02)
    static let helperSize = 0.8
    /// Lounge cats with no seat sleep in a cluster: 3 wide, this far apart (floor u, v), up to this many.
    static let clusterStep = 0.03
    static let clusterShown = 6

    /// Every cat's place, plus "+N" notes (text, floor point).
    func layout(in room: BuiltRoom) -> (cats: [SceneCat], notes: [(String, FloorPoint)]) {
        let byId = Dictionary(agents.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var cats: [SceneCat] = [], notes: [(String, FloorPoint)] = []
        var anchor: [String: FloorPoint] = [:]

        if lounge {
            for (i, id) in seating.lounge.enumerated() {
                guard let id, let agent = byId[id], room.seats.indices.contains(i) else { continue }
                let spot = room.seats[i]
                // simulation-engine.ts perches: only a raised spot puts the cat up on its prop (room.ts spotOwner).
                cats.append(SceneCat(agent: agent, kind: .seat, at: spot.standAt, lift: spot.lift, size: 1, pose: .sleeping,
                                     direction: "front-left", perch: spot.lift > 0 ? spot.owner : nil, desk: nil))
                anchor[id] = spot.standAt
            }
            // The rest cluster on the first rug spot, else the floor's centre.
            let rugs = Set(room.rugs.map(\.id))
            let base = room.seats.first { rugs.contains($0.owner) }?.standAt ?? FloorPoint(u: 0.5, v: 0.5)
            let seated = Set(seating.lounge.compactMap { $0 })
            let extra = agents.filter { !$0.isSubagent && !seated.contains($0.id) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for (j, agent) in extra.prefix(Self.clusterShown).enumerated() {
                let at = FloorPoint(u: base.u + Double(j % 3 - 1) * Self.clusterStep, v: base.v + Double(j / 3) * Self.clusterStep)
                cats.append(SceneCat(agent: agent, kind: .seat, at: at, lift: 0, size: 1, pose: .sleeping,
                                     direction: "front-left", perch: nil, desk: nil))
                anchor[agent.id] = at
            }
            if extra.count > Self.clusterShown {
                notes.append(("+\(extra.count - Self.clusterShown) asleep",
                              FloorPoint(u: base.u, v: base.v + Double((Self.clusterShown + 2) / 3) * Self.clusterStep)))
            }
        } else {
            let desks = Dictionary(room.desks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for (i, id) in seating.desks.enumerated() {
                guard let id, let agent = byId[id], deskIds.indices.contains(i), let desk = desks[deskIds[i]] else { continue }
                var seated = agent
                seated.desk = AgentDesk(id: desk.design, flip: desk.flip, rear: desk.rear)
                let scene = DeskScene(seated)
                cats.append(SceneCat(agent: agent, kind: .desk, at: desk.standAt, lift: 0, size: 1, pose: scene.pose,
                                     direction: agent.status == .working ? desk.facing : scene.direction, perch: nil, desk: desk.rect))
                anchor[id] = desk.standAt
            }
        }
        // Helpers beside their parent.
        for (parent, helpers) in seating.nearby.sorted(by: { $0.key < $1.key }) {
            guard let base = anchor[parent] else { continue }
            func beside(_ k: Int) -> FloorPoint {
                FloorPoint(u: base.u + Self.helperStep.u * Double(k + 1), v: base.v + Self.helperStep.v * Double(k + 1))
            }
            for (k, id) in helpers.enumerated() {
                guard let agent = byId[id] else { continue }
                cats.append(SceneCat(agent: agent, kind: .helper, at: beside(k), lift: 0, size: Self.helperSize, pose: .standing,
                                     direction: "front-left", perch: nil, desk: nil))
            }
            if let more = seating.nearbyOverflow[parent] { notes.append(("+\(more)", beside(helpers.count))) }
        }
        // The queue at the elevator's waiting places.
        let door = room.elevator?.standAt ?? FloorPoint(u: 0.5, v: 0.5)
        for (i, id) in seating.queue.enumerated() {
            guard let agent = byId[id] else { continue }
            cats.append(SceneCat(agent: agent, kind: .queue, at: ElevatorTrip.waitingPlace(door, index: i), lift: 0,
                                 size: agent.isSubagent ? Self.helperSize : 1, pose: .standing,
                                 direction: "front-left", perch: nil, desk: nil))
        }
        if seating.queueOverflow > 0 {
            let last = ElevatorTrip.waitingPlace(door, index: 2)
            notes.append(("+\(seating.queueOverflow)", FloorPoint(u: last.u + ElevatorTrip.waitSpread.u, v: last.v + ElevatorTrip.waitSpread.v)))
        }
        return (cats, notes)
    }
}

/// The live layer: cats at their real desks and seats, each at Cat Office's depth (catZ); a desk, prop or fixture in
/// front of a cat it overlaps is drawn again over it. Rings, "!" bubbles and name pills (only those that don't
/// overlap at the current zoom) on top.
struct SceneCats: View {
    let room: BuiltRoom
    let fit: SceneFit
    /// FloorScene's origin in "roomContent".
    let origin: CGPoint
    let catHeight: Double
    let cast: SceneCast
    @EnvironmentObject var state: AppState
    @EnvironmentObject var zoom: RoomZoom
    @Environment(\.officeNight) private var night
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.walkingCats) private var walkingCats

    /// Today's cats are drawn at catScale × 0.22 points per canvas px: a scene cat's size relative to that, for
    /// walkers, riders, rings and glows.
    static func relative(catHeight: Double, fit: SceneFit) -> CGFloat {
        CGFloat(catHeight / 210) * fit.scale / (DeskComposition.catScale * DeskStation.scale)
    }

    /// A cat as drawn: feet (points, lifted), canvas scale (points per canvas px), depth.
    private struct Drawn {
        let cat: SceneCat
        let feet: CGPoint
        let k: CGFloat
        let z: Int
        let figure: CGRect
        var canvas: CGRect { CGRect(x: feet.x - 180 * k, y: feet.y - 300 * k, width: 360 * k, height: 380 * k) }
        var rel: CGFloat { k / (DeskComposition.catScale * DeskStation.scale) }
    }

    private struct Cover {
        let key: String
        let image: String
        let rect: CGRect
        let mirrored: Bool
        let box: OccluderBox
    }

    private enum Item {
        case cat(Drawn)
        case cover(Cover)
    }

    private struct Entry: Identifiable {
        let z: Int
        let order: Int
        let id: String
        let item: Item
    }

    var body: some View {
        let (cats, notes) = cast.layout(in: room)
        let drawn = cats.compactMap(draw)
        let covers = room.desks.map { Cover(key: "desk:\($0.id)", image: $0.image, rect: $0.rect, mirrored: $0.flip, box: $0.box) }
            + room.props.compactMap { p in p.image.map { Cover(key: "prop:\(p.id)", image: $0, rect: p.rect, mirrored: p.mirrored, box: p.box) } }
            + room.fixtures.compactMap { f in f.image.map { Cover(key: "fixture:\(f.id)", image: $0, rect: f.rect, mirrored: f.mirrored, box: f.box) } }
        // Furniture over a cat it overlaps, by depth.
        let shownCovers = covers.filter { c in drawn.contains { d in c.box.z > d.z && Self.overlaps(d.figure, c.box.rect) } }
        let items = drawn.map { Entry(z: $0.z, order: 0, id: $0.cat.agent.id, item: .cat($0)) }
            + shownCovers.map { Entry(z: $0.box.z, order: 1, id: $0.key, item: .cover($0)) }
        let sorted = items.sorted { ($0.z, $0.order, $0.id) < ($1.z, $1.order, $1.id) }
        let scale = zoom.view.scale
        let pills = Dictionary(drawn.map { ($0.cat.agent.id, pillRect($0, scale: scale)) }, uniquingKeysWith: { a, _ in a })
        // "+N" notes are always shown: they go first (their keys sort before any agent id), names fit round them.
        let noteRects = Dictionary(notes.enumerated().map { i, note -> (String, CGRect) in
            let p = fit.point(room.frame.px(note.1)), size = Self.pillSize(note.0, detail: nil)
            return ("\u{0}note\(i)", CGRect(x: p.x * scale, y: p.y * scale, width: size.width, height: size.height))
        }, uniquingKeysWith: { a, _ in a })
        let needy = Set(drawn.map(\.cat.agent).filter(needsYou).map(\.id)).union(noteRects.keys)
        let shownPills = PillLayout.visible(pills.mapValues(\.rect).merging(noteRects) { a, _ in a }, priority: needy)

        ZStack(alignment: .topLeading) {
            ForEach(sorted) { entry in
                switch entry.item {
                case .cat(let d): catView(d)
                case .cover(let c): coverView(c)
                }
            }
            ForEach(drawn.filter { $0.cat.agent.status == .waiting }, id: \.cat.agent.id) { d in
                Text("!").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 16, height: 16).background(Circle().fill(Color(hex: 0xE5484D)))
                    .offset(x: d.feet.x + 8 * d.rel, y: d.canvas.minY + 2 * d.rel)
            }
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                let p = fit.point(room.frame.px(note.1))
                RoomPill(text: note.0).fixedSize()
                    .scaleEffect(1 / scale, anchor: .topLeading)
                    .offset(x: p.x, y: p.y)
            }
            ForEach(drawn.filter { shownPills.contains($0.cat.agent.id) }, id: \.cat.agent.id) { d in
                let pill = pills[d.cat.agent.id]!
                namePill(d.cat.agent)
                    .frame(width: pill.size.width, height: pill.size.height)
                    .scaleEffect(1 / scale, anchor: .top)
                    .offset(x: d.feet.x - pill.size.width / 2, y: d.feet.y + 3 / scale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .preference(key: CatFeetKey.self, value: Dictionary(drawn.map { ($0.cat.agent.id, shift($0.feet)) }, uniquingKeysWith: { a, _ in a }))
        .preference(key: CatFramesKey.self, value: Dictionary(drawn.map { ($0.cat.agent.id, fit.rect($0.figure).offsetBy(dx: origin.x, dy: origin.y)) },
                                                              uniquingKeysWith: { a, _ in a }))
    }

    private func shift(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + origin.x, y: p.y + origin.y) }

    /// occlusion.ts's strict overlap.
    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
    }

    private func needsYou(_ a: OfficeAgent) -> Bool { a.status == .waiting || state.attention.contains(a.key) }

    private func draw(_ cat: SceneCat) -> Drawn? {
        let px = room.frame.px(cat.at)
        guard px.x.isFinite, px.y.isFinite, cat.lift.isFinite else { return nil }
        let h = catHeight * cat.size
        let figure = RoomGeometry.figure(feet: px, catHeight: h, lift: cat.lift)
        let z = RoomGeometry.catZ(feet: cat.at, figure: figure, boxes: room.boxes, perch: cat.perch)
        let ground = fit.point(px)
        let feet = CGPoint(x: ground.x, y: ground.y - CGFloat(cat.lift) * fit.scale)
        return Drawn(cat: cat, feet: feet, k: CGFloat(h / 210) * fit.scale, z: z, figure: figure)
    }

    /// Where a cat's name pill would go, in view points after zoom: centred under its feet, the pill's own size.
    private func pillRect(_ d: Drawn, scale: CGFloat) -> (rect: CGRect, size: CGSize) {
        let size = Self.pillSize(d.cat.agent.label, detail: detail(d.cat.agent))
        return (CGRect(x: d.feet.x * scale - size.width / 2, y: d.feet.y * scale + 3, width: size.width, height: size.height), size)
    }

    private func detail(_ a: OfficeAgent) -> String {
        Format.statusText(a.status, needsYou: needsYou(a), since: a.waitingSince ?? state.statusSince[a.key])
    }

    /// RoomPill's size: a 9pt semibold line and an 8pt detail line, padded 6 × 2; a name pill is at most 84 wide.
    static func pillSize(_ text: String, detail: String?) -> CGSize {
        let a = NSFont.systemFont(ofSize: 9, weight: .semibold), b = NSFont.systemFont(ofSize: 8)
        let line = { (f: NSFont) in ceil(f.ascender - f.descender + f.leading) }
        let tw = ceil((text as NSString).size(withAttributes: [.font: a]).width)
        guard let detail else { return CGSize(width: tw + 12, height: line(a) + 4) }
        let w = max(tw, ceil((detail as NSString).size(withAttributes: [.font: b]).width))
        return CGSize(width: min(84, w + 12), height: line(a) + line(b) + 4)
    }

    private func namePill(_ a: OfficeAgent) -> some View {
        let needy = needsYou(a)
        return RoomPill(text: a.label, detail: detail(a), detailColor: needy ? Theme.waiting : Theme.color(a.status))
    }

    @ViewBuilder
    private func catView(_ d: Drawn) -> some View {
        let agent = d.cat.agent
        let rel = d.rel
        ZStack(alignment: .topLeading) {
            if agent.status == .waiting && d.cat.kind != .seat {
                Ellipse()
                    .fill(RadialGradient(colors: [Theme.waiting.opacity(0.6), Theme.waiting.opacity(0)], center: .center, startRadius: 3, endRadius: 46))
                    .frame(width: 96, height: 30)
                    .scaleEffect(rel)
                    .offset(x: d.feet.x - 48, y: d.feet.y - 15)
            }
            if d.cat.kind != .seat {
                StatusRing(status: agent.status, attention: false).frame(width: 40, height: 10)
                    .scaleEffect(0.8 * rel)
                    .offset(x: d.feet.x - 20, y: d.feet.y - 5)
            }
            if let desk = d.cat.desk, agent.status == .working && night {
                let r = fit.rect(desk)
                Ellipse()
                    .fill(RadialGradient(colors: [Night.screen.opacity(0.55), Night.screen.opacity(0)], center: .center, startRadius: 2, endRadius: 40))
                    .frame(width: 80, height: 50)
                    .scaleEffect(rel)
                    .offset(x: r.midX - 40, y: r.minY - 6)
                    .blendMode(.screen)
            }
            sprite(d).opacity(walkingCats.contains(agent.id) ? 0 : 1)
        }
    }

    private func sprite(_ d: Drawn) -> some View {
        let agent = d.cat.agent
        let cat = CatPicker.cat(for: agent, catIds: state.catIds)
        let pose = d.cat.pose, direction = d.cat.direction
        let r = d.canvas
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || agent.status == .waiting)) { context in
            let motion = reduceMotion ? CatMotion(offsetY: 0, scale: 1)
                : CatMotion.at(status: agent.status, time: context.date.timeIntervalSinceReferenceDate)
            SpriteImage(key: "\(cat)-\(pose.rawValue)-\(direction)", fallback: Theme.color(agent.status)) {
                await state.art.catImage(cat: cat, pose: pose, direction: direction)
            }
            .frame(width: r.width, height: r.height)
            .colorMultiply(!night ? .white : agent.status == .idle ? Night.asleep : Night.furniture)
            .scaleEffect(motion.scale, anchor: .bottom)
            .offset(x: r.minX, y: r.minY + motion.offsetY * d.rel)
        }
    }

    private func coverView(_ c: Cover) -> some View {
        let r = fit.rect(c.rect)
        return SpriteImage(key: c.image, fallback: nil, mode: .stretch) { await state.art.image(path: c.image, maxPixelSize: 1024) }
            .frame(width: r.width, height: r.height)
            .scaleEffect(x: c.mirrored ? -1 : 1, y: 1)
            .colorMultiply(night ? Night.furniture : .white)
            .offset(x: r.minX, y: r.minY)
            .allowsHitTesting(false)
    }
}

/// Pictures of built rooms, by floor, night and scale (pixels per world px); an entry is kept only for the room it
/// was drawn from. Art is loaded first (ArtCache), then the room is drawn at once with Core Graphics.
@MainActor
final class RoomImageCache {
    static let shared = RoomImageCache()

    private struct Key: Hashable {
        let floorId: Int
        let night: Bool
        let scale: Int
    }

    private var entries: [Key: (room: BuiltRoom, image: NSImage)] = [:]
    /// Art by path, as loaded.
    private var art: [String: CGImage] = [:]
    /// Art multiplied by a night colour, by "tint|path".
    private var tinted: [String: CGImage] = [:]

    /// Scales compared to a thousandth, so layout jitter doesn't redraw.
    nonisolated static func quantized(_ scale: CGFloat) -> CGFloat { (scale * 1000).rounded() / 1000 }

    /// World px the picture covers: the floor and walls, everything standing in the room, and a margin for shadows.
    nonisolated static func imageBounds(_ room: BuiltRoom) -> CGRect {
        var r = room.bounds
        for x in room.desks.map(\.rect) + room.props.map(\.rect) + room.fixtures.map(\.rect) { r = r.union(x) }
        return r.insetBy(dx: -24, dy: -24).integral
    }

    private func key(_ room: BuiltRoom, _ night: Bool, _ scale: CGFloat) -> Key {
        Key(floorId: room.floorId, night: night, scale: Int((scale * 1000).rounded()))
    }

    func cached(_ room: BuiltRoom, night: Bool, scale: CGFloat) -> NSImage? {
        guard let e = entries[key(room, night, scale)], e.room == room else { return nil }
        return e.image
    }

    func image(for room: BuiltRoom, night: Bool, scale: CGFloat, art cache: ArtCache) async -> NSImage? {
        if let hit = cached(room, night: night, scale: scale) { return hit }
        let needs = RoomPainter.art(room).filter { art[$0.key] == nil }
        let loaded = await withTaskGroup(of: (String, Data?).self) { group in
            for (path, natural) in needs {
                // Sliced and repeated art is measured in its own pixels: loaded whole. Sprites only need to be sharp.
                group.addTask { (path, await cache.image(path: path, maxPixelSize: natural ? 4096 : 1024)) }
            }
            var out: [(String, Data?)] = []
            for await r in group { out.append(r) }
            return out
        }
        for (path, data) in loaded {
            guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            art[path] = image
        }
        let painter = RoomPainter(room: room, scale: scale, night: night) { [self] path, tint in picture(path, tint: tint) }
        guard let cg = painter.draw() else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / FloorScene.pixelsPerPoint,
                                                      height: CGFloat(cg.height) / FloorScene.pixelsPerPoint))
        entries[key(room, night, scale)] = (room, image)
        return image
    }

    private func picture(_ path: String, tint: RoomPainter.Tint?) -> CGImage? {
        guard let image = art[path] else { return nil }
        guard let tint else { return image }
        let k = "\(tint)|\(path)"
        if let done = tinted[k] { return done }
        let out = RoomPainter.multiply(image, tint.rgb)
        tinted[k] = out
        return out
    }
}

/// Draws a BuiltRoom in world px, in RoomShell.tsx's order: the floor and its rugs, each wall with its items, the
/// contact shadows, then desks, props and fixtures in depth order.
struct RoomPainter {
    enum Tint: CustomStringConvertible {
        /// Night.room: floor and walls.
        case room
        /// Night.furniture: everything else.
        case furniture

        var description: String { self == .room ? "room" : "furniture" }

        var rgb: (CGFloat, CGFloat, CGFloat) {
            let c = NSColor(self == .room ? Night.room : Night.furniture).usingColorSpace(.sRGB) ?? .white
            return (c.redComponent, c.greenComponent, c.blueComponent)
        }
    }

    let room: BuiltRoom
    /// Pixels per world px.
    let scale: CGFloat
    let night: Bool
    let picture: (String, Tint?) -> CGImage?

    /// RoomShell.tsx: the floor's colour without a material.
    static let floorColor = "#e3a56c"
    /// RoomProps.tsx PLACEHOLDER_COLOR.
    static let placeholderColor = "#c9a27a"
    /// desks.ts / RoomProps.tsx SHADOW_SPREAD (floor units).
    static let shadowSpread = 0.004

    /// Every picture the room draws: path, and whether it's needed at its own pixel size (slices, repeats).
    static func art(_ room: BuiltRoom) -> [(key: String, natural: Bool)] {
        var out: [String: Bool] = [:]
        func add(_ p: String?, _ natural: Bool = false) {
            guard let p, !p.isEmpty else { return }
            out[p] = (out[p] ?? false) || natural
        }
        add(room.floorTexture?.image)
        add(room.wallTexture?.image, true)
        room.rugs.forEach { add($0.image) }
        for item in room.wallItems {
            add(item.image)
            for piece in item.pieces {
                switch piece {
                case .nineSlice(let image, _, _), .repeatX(let image, _): add(image, true)
                case .stretch(let image, _), .decor(let image, _): add(image)
                case .fill: break
                }
            }
        }
        room.desks.forEach { add($0.image) }
        room.props.forEach { add($0.image) }
        room.fixtures.forEach { add($0.image) }
        return out.map { (key: $0.key, natural: $0.value) }
    }

    private func image(_ path: String?, _ tint: Tint) -> CGImage? {
        guard let path, !path.isEmpty else { return nil }
        return picture(path, night ? tint : nil)
    }

    func draw() -> CGImage? {
        let b = RoomImageCache.imageBounds(room)
        let w = Int((b.width * scale).rounded(.up)), h = Int((b.height * scale).rounded(.up))
        guard w > 0, h > 0, w * h < 40_000_000, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        // World px, y down.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -b.minX, y: -b.minY)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        defer { NSGraphicsContext.current = previous }

        drawFloor(ctx)
        for side in [WallSide.left, .right] { drawWall(ctx, side) }
        drawShadows(ctx)
        drawStanding(ctx)
        return ctx.makeImage()
    }

    // MARK: Floor (RoomShell.tsx 561-571, 618-624)

    private func drawFloor(_ ctx: CGContext) {
        let plane = room.frame.plane
        let size = CGFloat(plane.size)
        ctx.saveGState()
        ctx.concatenate(plane.transform)
        ctx.clip(to: CGRect(x: 0, y: 0, width: size, height: size))
        fill(ctx, CGRect(x: 0, y: 0, width: size, height: size), room.floorTexture?.color ?? Self.floorColor, .room)
        if let m = room.floorTexture, let img = image(m.image, .room) {
            let tile = m.tile ?? [512, 512]
            let tw = CGFloat(tile.first ?? 512), th = CGFloat(tile.count > 1 ? tile[1] : 512)
            tiled(ctx, img, origin: .zero, tile: CGSize(width: tw, height: th))
        }
        for rug in room.rugs { drawRug(ctx, rug) }
        ctx.restoreGState()
    }

    /// RoomShell.tsx Rug: the art over its box, or a quarter turn round in a box with the sides swapped.
    private func drawRug(_ ctx: CGContext, _ rug: PlacedRug) {
        guard let img = image(rug.image, .furniture) else {
            // A rug without art (room.css .room-rug--plain): its colour, edged.
            let path = CGPath(roundedRect: rug.rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(color("#f6ecdc", .furniture))
            ctx.fillPath()
            ctx.addPath(CGPath(roundedRect: rug.rect.insetBy(dx: 3, dy: 3), cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.setStrokeColor(CGColor(srgbRed: 91 / 255, green: 58 / 255, blue: 44 / 255, alpha: 0.35))
            ctx.setLineWidth(6)
            ctx.strokePath()
            return
        }
        guard rug.turned else { put(ctx, img, in: rug.rect); return }
        ctx.saveGState()
        ctx.translateBy(x: rug.rect.midX, y: rug.rect.midY)
        ctx.rotate(by: .pi / 2)
        put(ctx, img, in: CGRect(x: -rug.rect.height / 2, y: -rug.rect.width / 2, width: rug.rect.height, height: rug.rect.width))
        ctx.restoreGState()
    }

    // MARK: Walls (RoomShell.tsx 339-349, 367-387)

    private func drawWall(_ ctx: CGContext, _ side: WallSide) {
        let wall = room.frame.wall(side, height: room.wallHeight)
        let length = CGFloat(wall.length), height = CGFloat(room.wallHeight)
        ctx.saveGState()
        ctx.concatenate(wall.transform)
        // Wall items stay on their wall (room.css .room-wall: overflow hidden).
        ctx.clip(to: CGRect(x: 0, y: 0, width: length, height: height))
        let material = room.wallTexture
        fill(ctx, CGRect(x: 0, y: 0, width: length, height: height), material?.color ?? "#fdeee0", .room)
        if let m = material, let img = image(m.image, .room) { plaster(ctx, img, m, length: length, height: height) }
        for item in room.wallItems where item.wall == side { drawWallItem(ctx, item) }
        ctx.restoreGState()
    }

    /// plasterStyle: 3-sliced (top trim and baseboard as drawn, the rows between repeated, all tiles centred like
    /// border-image `repeat`), reaching `floorRows` below the wall's foot; without slices stretched to the height.
    private func plaster(_ ctx: CGContext, _ img: CGImage, _ m: WallMaterial, length: CGFloat, height: CGFloat) {
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        guard let slice = m.slice else {
            let tw = CGFloat(m.tile?.first ?? 200)
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: length, height: height))
            tiled(ctx, img, origin: .zero, tile: CGSize(width: tw, height: height))
            ctx.restoreGState()
            return
        }
        let total = height + CGFloat(m.floorRows ?? 0)
        let top = CGFloat(slice.top ?? 0).rounded(), bottom = CGFloat(slice.bottom ?? 0).rounded()
        let x0 = Self.centredStart(length, iw)
        func band(_ rows: CGRect, at y: CGFloat, height bh: CGFloat) {
            guard rows.height > 0, bh > 0, let part = img.cropping(to: rows) else { return }
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: y, width: length, height: bh))
            let y0 = rows.height == bh ? y : y + Self.centredStart(bh, rows.height)
            tiled(ctx, part, origin: CGPoint(x: x0, y: y0), tile: CGSize(width: iw, height: rows.height))
            ctx.restoreGState()
        }
        band(CGRect(x: 0, y: top, width: iw, height: ih - top - bottom), at: top, height: total - top - bottom)
        band(CGRect(x: 0, y: 0, width: iw, height: top), at: 0, height: top)
        band(CGRect(x: 0, y: ih - bottom, width: iw, height: bottom), at: total - bottom, height: bottom)
    }

    /// Where the first of a row of `tile`-long tiles centred on `length` starts (≤ 0).
    static func centredStart(_ length: CGFloat, _ tile: CGFloat) -> CGFloat {
        guard tile > 0 else { return 0 }
        let first = (length - tile) / 2
        return first - (first / tile).rounded(.up) * tile
    }

    /// RoomShell.tsx WallItem: mirrored about its box's middle; a window's layers, or its art cut at the sill; the
    /// elevator's floor number on its plate (never mirrored).
    private func drawWallItem(_ ctx: CGContext, _ item: PlacedWallItem) {
        let box = item.box
        ctx.saveGState()
        if item.mirrored { mirror(ctx, about: box.midX) }
        if !item.pieces.isEmpty {
            ctx.translateBy(x: box.minX, y: box.minY)
            for piece in item.pieces { drawPiece(ctx, piece) }
        } else if let img = image(item.image, .furniture) {
            if let keep = item.clipHeight { ctx.clip(to: CGRect(x: box.minX, y: box.minY, width: box.width, height: CGFloat(keep))) }
            put(ctx, img, in: box)
        }
        ctx.restoreGState()
        if let plate = item.plate { drawPlate(plate) }
    }

    private func drawPiece(_ ctx: CGContext, _ piece: WindowPiece) {
        switch piece {
        case .nineSlice(let path, let rect, let slice):
            if let img = image(path, .furniture) { nineSlice(ctx, img, rect, slice) }
        case .stretch(let path, let rect), .decor(let path, let rect):
            if let img = image(path, .furniture) { put(ctx, img, in: rect) }
        case .repeatX(let path, let rect):
            // The skyline: `auto <height>` tiles along the bottom, from the left.
            guard let img = image(path, .furniture), img.height > 0, rect.height > 0 else { return }
            ctx.saveGState()
            ctx.clip(to: rect)
            tiled(ctx, img, origin: rect.origin, tile: CGSize(width: CGFloat(img.width) * rect.height / CGFloat(img.height), height: rect.height))
            ctx.restoreGState()
        case .fill(let hex, let rect):
            fill(ctx, rect, hex, .furniture)
        }
    }

    /// border-image `slice fill / widths stretch` with the widths equal to the slices: corners as drawn, edges and
    /// middle stretched.
    private func nineSlice(_ ctx: CGContext, _ img: CGImage, _ rect: CGRect, _ s: SliceDef) {
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        let l = CGFloat(s.left ?? 0), r = CGFloat(s.right ?? 0), t = CGFloat(s.top ?? 0), b = CGFloat(s.bottom ?? 0)
        let sx = [0, l, iw - r, iw], sy = [0, t, ih - b, ih]
        let dx = [rect.minX, rect.minX + l, rect.maxX - r, rect.maxX], dy = [rect.minY, rect.minY + t, rect.maxY - b, rect.maxY]
        for i in 0..<3 {
            for j in 0..<3 {
                let src = CGRect(x: sx[i], y: sy[j], width: sx[i + 1] - sx[i], height: sy[j + 1] - sy[j])
                let dst = CGRect(x: dx[i], y: dy[j], width: dx[i + 1] - dx[i], height: dy[j + 1] - dy[j])
                guard src.width > 0, src.height > 0, dst.width > 0, dst.height > 0, let part = img.cropping(to: src) else { continue }
                put(ctx, part, in: dst)
            }
        }
    }

    /// RoomShell.tsx 315-330 and room.css .elevator__number: the floor number, bold, 0.8 × the plate's height.
    private func drawPlate(_ plate: CGRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let ink = NSColor(cgColor: color("#f4ece6", .furniture)) ?? .white
        let text = NSAttributedString(string: "\(room.floorId)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: plate.height * 0.8, weight: .bold),
            .foregroundColor: ink, .paragraphStyle: style,
        ])
        let h = text.size().height
        text.draw(in: CGRect(x: plate.minX, y: plate.midY - h / 2, width: plate.width, height: h))
    }

    // MARK: Shadows (Desks.tsx 35-54, RoomProps.tsx 94-130; app.css .desk-shadows)

    private func drawShadows(_ ctx: CGContext) {
        let s = Self.shadowSpread
        func corners(_ f: Footprint) -> [CGPoint] {
            [FloorPoint(u: f.u0 - s, v: f.v0 - s), FloorPoint(u: f.u1 + s, v: f.v0 - s),
             FloorPoint(u: f.u1 + s, v: f.v1 + s), FloorPoint(u: f.u0 - s, v: f.v1 + s)]
                .map { let p = room.frame.px($0); return CGPoint(x: p.x, y: p.y) }
        }
        shadow(ctx, room.desks.map { corners($0.footprint) }, sigma: 9)
        shadow(ctx, room.props.map { corners($0.footprint) }, sigma: 7)
    }

    /// Polygons blurred by `sigma` world px, in rgba(74, 52, 38, 0.3): each drawn far off to the right, its shadow
    /// cast back into place (shadow offsets are in device pixels, unaffected by the transform).
    private func shadow(_ ctx: CGContext, _ polygons: [[CGPoint]], sigma: CGFloat) {
        guard !polygons.isEmpty else { return }
        let away = RoomImageCache.imageBounds(room).width + 4 * sigma + 100
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: -away * scale, height: 0), blur: 2 * sigma * scale,
                      color: CGColor(srgbRed: 74 / 255, green: 52 / 255, blue: 38 / 255, alpha: 0.3))
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        for poly in polygons {
            guard let first = poly.first else { continue }
            ctx.move(to: CGPoint(x: first.x + away, y: first.y))
            for p in poly.dropFirst() { ctx.addLine(to: CGPoint(x: p.x + away, y: p.y)) }
            ctx.closePath()
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    // MARK: Desks, props and fixtures in depth order (Office.tsx's cats' layer)

    private func drawStanding(_ ctx: CGContext) {
        enum Thing { case desk(PlacedDesk), prop(PlacedProp), fixture(PlacedFixture) }
        var things: [(z: Int, kind: Int, index: Int, thing: Thing)] = []
        for (i, d) in room.desks.enumerated() { things.append((d.box.z, 0, i, .desk(d))) }
        for (i, p) in room.props.enumerated() { things.append((p.box.z, 1, i, .prop(p))) }
        for (i, f) in room.fixtures.enumerated() { things.append((f.box.z, 2, i, .fixture(f))) }
        things.sort { ($0.z, $0.kind, $0.index) < ($1.z, $1.kind, $1.index) }
        for t in things {
            switch t.thing {
            case .desk(let d): sprite(ctx, image(d.image, .furniture), d.rect, mirrored: d.flip)
            case .prop(let p):
                if p.image != nil { sprite(ctx, image(p.image, .furniture), p.rect, mirrored: p.mirrored) } else { placeholder(ctx, p) }
            case .fixture(let f): sprite(ctx, image(f.image, .furniture), f.rect, mirrored: f.mirrored)
            }
        }
    }

    private func sprite(_ ctx: CGContext, _ img: CGImage?, _ rect: CGRect, mirrored: Bool) {
        guard let img else { return }
        ctx.saveGState()
        if mirrored { mirror(ctx, about: rect.midX) }
        put(ctx, img, in: rect)
        ctx.restoreGState()
    }

    /// RoomProps.tsx PlaceholderBox: an isometric box of the footprint up to the top of its screen box.
    private func placeholder(_ ctx: CGContext, _ p: PlacedProp) {
        let f = p.footprint
        let c = [FloorPoint(u: f.u0, v: f.v0), FloorPoint(u: f.u1, v: f.v0), FloorPoint(u: f.u1, v: f.v1), FloorPoint(u: f.u0, v: f.v1)]
            .map { let q = room.frame.px($0); return CGPoint(x: q.x, y: q.y) }
        let tall = (c.map(\.y).min() ?? p.rect.minY) - p.rect.minY
        let up = { (q: CGPoint) in CGPoint(x: q.x, y: q.y - tall) }
        let (back, left, front, right) = (c[0], c[1], c[2], c[3])
        func poly(_ ps: [CGPoint], _ k: Double) {
            ctx.addLines(between: ps)
            ctx.closePath()
            ctx.setFillColor(color(Self.placeholderColor, .furniture, shade: k))
            ctx.fillPath()
        }
        poly([left, front, up(front), up(left)], 0)
        poly([front, right, up(right), up(front)], -0.18)
        poly([up(back), up(left), up(front), up(right)], 0.25)
    }

    // MARK: Drawing helpers

    /// An image over `rect` (world px, y down): drawn the right way up.
    private func put(_ ctx: CGContext, _ img: CGImage, in rect: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// `img` repeated over the current clip in `tile`-sized tiles, one with its top-left at `origin`.
    private func tiled(_ ctx: CGContext, _ img: CGImage, origin: CGPoint, tile: CGSize) {
        guard tile.width > 0, tile.height > 0 else { return }
        // Drawn by row and column: the clip keeps the count down; tiles overlap a hair so no seam shows.
        let clip = ctx.boundingBoxOfClipPath
        guard clip.width.isFinite, clip.height.isFinite else { return }
        let i0 = ((clip.minX - origin.x) / tile.width).rounded(.down), i1 = ((clip.maxX - origin.x) / tile.width).rounded(.up)
        let j0 = ((clip.minY - origin.y) / tile.height).rounded(.down), j1 = ((clip.maxY - origin.y) / tile.height).rounded(.up)
        guard (i1 - i0) * (j1 - j0) < 20_000 else { return }
        let lap = 0.5 / scale
        var j = j0
        while j < j1 {
            var i = i0
            while i < i1 {
                put(ctx, img, in: CGRect(x: origin.x + i * tile.width, y: origin.y + j * tile.height,
                                         width: tile.width + lap, height: tile.height + lap))
                i += 1
            }
            j += 1
        }
    }

    private func mirror(_ ctx: CGContext, about x: CGFloat) {
        ctx.translateBy(x: x, y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.translateBy(x: -x, y: 0)
    }

    private func fill(_ ctx: CGContext, _ rect: CGRect, _ hex: String, _ tint: Tint) {
        ctx.setFillColor(color(hex, tint))
        ctx.fill(rect)
    }

    /// "#rrggbb", shaded like RoomProps.tsx shade (k < 0 towards black, k > 0 towards white), times the night tint.
    private func color(_ hex: String, _ tint: Tint, shade k: Double = 0) -> CGColor {
        let n = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xEADBC8
        func mix(_ c: UInt32) -> CGFloat {
            let v = Double(c)
            return CGFloat((k < 0 ? v * (1 + k) : v + (255 - v) * k).rounded()) / 255
        }
        var (r, g, b) = (mix((n >> 16) & 255), mix((n >> 8) & 255), mix(n & 255))
        if night {
            let m = tint.rgb
            r *= m.0; g *= m.1; b *= m.2
        }
        return CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    /// The image with each pixel multiplied by `rgb` (CSS/SwiftUI colorMultiply), alpha kept.
    static func multiply(_ image: CGImage, _ rgb: (CGFloat, CGFloat, CGFloat)) -> CGImage? {
        let w = image.width, h = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let row = ctx.bytesPerRow
        let px = data.bindMemory(to: UInt8.self, capacity: row * h)
        // (Swift's >> binds tighter than *: the products are bracketed.)
        let m = [rgb.0, rgb.1, rgb.2].map { UInt32(max(0, min(1, $0)) * 256) }
        for y in 0..<h {
            let base = y * row
            for x in 0..<w {
                let i = base + x * 4
                px[i] = UInt8((UInt32(px[i]) * m[0]) >> 8)
                px[i + 1] = UInt8((UInt32(px[i + 1]) * m[1]) >> 8)
                px[i + 2] = UInt8((UInt32(px[i + 2]) * m[2]) >> 8)
            }
        }
        return ctx.makeImage()
    }
}
