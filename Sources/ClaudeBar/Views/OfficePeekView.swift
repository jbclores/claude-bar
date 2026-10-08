import AppKit
import ClaudeBarCore
import SwiftUI

/// Where the pointer is inside the peek, fed by PeekContainerView (AppKit tracking works while ClaudeBar
/// isn't the active app; SwiftUI's onHover doesn't reliably).
@MainActor
final class PeekPointer: ObservableObject {
    @Published var location: CGPoint?
}

/// A cat's feet as drawn, in "roomContent" (lifted on a raised seat), and on a built floor the floor point it stands
/// on: walks route between floor points and hop up or down to the drawn feet (WalkRouter).
struct CatFeet: Equatable {
    var point: CGPoint
    var floor: FloorPoint?
}

/// Where each cat's feet are (agent id → CatFeet), for walking it to its next spot.
struct CatFeetKey: PreferenceKey {
    static let defaultValue: [String: CatFeet] = [:]
    static func reduce(value: inout [String: CatFeet], nextValue: () -> [String: CatFeet]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct WalkingCatsKey: EnvironmentKey {
    static let defaultValue: Set<String> = []
}

extension EnvironmentValues {
    /// Cats on their way somewhere: their spot stays empty until they arrive.
    var walkingCats: Set<String> {
        get { self[WalkingCatsKey.self] }
        set { self[WalkingCatsKey.self] = newValue }
    }
}

/// Each cat's hover frame, depth and feet (agent id → in "roomContent").
struct CatFramesKey: PreferenceKey {
    static let defaultValue: [String: CatHit] = [:]
    static func reduce(value: inout [String: CatHit], nextValue: () -> [String: CatHit]) {
        value.merge(nextValue()) { $1 }
    }
}

extension CatHit {
    /// A cat drawn without depth (the simple room): its feet at the bottom middle of its frame.
    init(frame: CGRect) { self.init(frame: frame, z: 0, feet: CGPoint(x: frame.midX, y: frame.maxY)) }
}

/// "· 2 cats · Claude OK" (or hindered) after the peek's floor name: the cats on that floor, as the Office tab's floor
/// menu counts them (not the whole office, which read as if they were all on the floor shown).
struct OfficeSummary: View {
    let office: OfficeSnapshot
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Text("· \(count) cat\(count == 1 ? "" : "s") ·").foregroundStyle(.secondary)
            Text(office.claudeHindered ? "Claude hindered" : "Claude OK")
                .foregroundStyle(office.claudeHindered ? Theme.waiting : .secondary)
        }
    }
}

/// Changes whenever Cat Office's art changed (an edited character or piece of furniture): sprites and room
/// pictures watching it load again.
@MainActor
final class ArtGeneration: ObservableObject {
    static let shared = ArtGeneration()
    @Published private(set) var value = 0

    /// Forgets every loaded sprite and room picture, and has them load again.
    func bump() {
        SpriteImage.loaded = [:]
        RoomImageCache.shared.forget()
        value += 1
    }
}

/// The tiny office: busy cats at desks, idle ones in the lounge, a card for the cat under the pointer; a sleeping
/// cat and the Start button while Cat Office is offline. Cat frames are measured in the "office" coordinate space,
/// which the parent sets up together with the PeekPointer it feeds.
struct OfficeRoomView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var pointer: PeekPointer
    @EnvironmentObject var zoom: RoomZoom
    @Environment(\.colorScheme) private var colorScheme
    @State private var catFrames: [String: CatHit] = [:]
    @State private var lastFeet: [String: CatFeet] = [:]
    @EnvironmentObject var floors: FloorSelection
    /// Who sits where, per floor, kept between updates so cats keep their desks and seats.
    @State private var seatings: [Int: FloorSeating] = [:]
    @State private var walks: [String: CatWalk] = [:]
    /// Each agent's floor at the last update, to notice floor changes.
    @State private var floorOf: [String: Int] = [:]
    /// Rides in progress, by agent id.
    @State private var rides: [String: Rider] = [:]
    /// Arrivals whose walk out of the elevator is scheduled: agent id → its trip's start.
    @State private var walkOuts: [String: Date] = [:]
    /// The cats' feet as last reported (CatFeetKey).
    @State private var shownFeet: [String: CatFeet] = [:]
    /// The building's floor ids at the last floor check.
    @State private var buildingFloors: [Int] = []
    /// Built floors' fits (FloorScene), by floor id, in "roomContent" points.
    @State private var fits: [Int: SceneFit] = [:]

    /// Changes when any agent's floor changes.
    private var floorKey: String {
        let agents = state.office?.agents ?? []
        return agents.compactMap { a in FloorPlan.floorId(for: a, among: agents, in: state.building, mirror: state.mirror).map { "\(a.id)@\($0)" } }
            .sorted().joined(separator: ",")
    }

    private func noticeFloorChanges() {
        let agents = state.office?.agents ?? []
        var next: [String: Int] = [:]
        for a in agents { if let f = FloorPlan.floorId(for: a, among: agents, in: state.building, mirror: state.mirror) { next[a.id] = f } }
        // A different building (Cat Office's floors replacing the fallback Lounge) moves cats without anyone riding.
        let floorIds = state.building.floors.map(\.id)
        defer { buildingFloors = floorIds }
        guard !reduceMotion, buildingFloors == floorIds else { floorOf = next; return }
        let now = Date()
        var waiting = 0
        for (id, to) in next {
            guard let from = floorOf[id], from != to, let agent = agents.first(where: { $0.id == id }) else { continue }
            // The walk to the elevator, from where the cat last stood on the shown floor (if it was there).
            let place = elevatorPlace(waiting)
            let walkIn = from == floorId ? lastFeet[id].map {
                WalkRouter.path(from: $0.point, fromFloor: $0.floor, to: place, toFloor: elevatorFloorPoint(waiting),
                                grid: state.navs[floorId], frame: state.rooms[floorId]?.frame, fit: fits[floorId])
            } : nil
            let speed = WalkPath.speed(for: id, base: CatWalk.baseSpeed)
            let trip = ElevatorTrip(from: from, to: to, start: now, walkIn: TimeInterval((walkIn?.length ?? 0) / speed))
            rides[id] = Rider(id: id, agent: agent, trip: trip, walkIn: walkIn, waitIndex: waiting)
            waiting += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + trip.doneTime.timeIntervalSince(now) + 0.1) {
                if rides[id]?.trip == trip { rides[id] = nil }
            }
        }
        floorOf = next
        // The arrival's spot may have been reported before its ride began: schedule its walk out of the elevator.
        if waiting > 0 { startWalks(to: shownFeet) }
    }

    /// Cats riding up to the shown floor: their spot stays empty until they've walked out of the elevator.
    private var arrivingHere: Set<String> {
        Set(rides.values.filter { $0.trip.to == floorId && Date() < $0.trip.doneTime }.map(\.id))
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 180

    private var hovered: OfficeAgent? { pointer.location.flatMap(cat(at:)) }

    /// The frontmost cat at a point in the office space (over the zoomed drawing).
    private func cat(at point: CGPoint) -> OfficeAgent? {
        guard let office = state.office, zoom.contains(point) else { return nil }
        // The pointer is over the zoomed drawing: find the room point under it.
        let room = zoom.view.unzoom(CGPoint(x: point.x - zoom.roomRect.minX, y: point.y - zoom.roomRect.minY))
        // The frontmost cat under the pointer (CatHit.frontmost), not whichever the dictionary lists first.
        guard let id = CatHit.frontmost(catFrames, at: room) else { return nil }
        return office.agents.first { $0.id == id }
    }

    /// The app's appearance already follows the ☀️/🌙 setting (AppState.applyLighting).
    private var night: Bool { colorScheme == .dark }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .topLeading) {
                if let built = state.rooms[floorId] {
                    // The floor as Cat Office lays it out, its cats at the real desks and seats.
                    FloorScene(room: built, floor: floor, catHeight: catHeight, cast: state.office == nil ? nil : cast(built))
                    if state.office == nil { offline }
                } else {
                    RoomBackdrop(floor: floor)
                    if state.office != nil {
                        room()
                    } else {
                        offline
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                WalkersLayer(walks: walks, catIds: state.catIds, legFrames: !reduceMotion, scale: catScale)
            }
            .overlay(alignment: .topLeading) {
                RidersLayer(rides: Array(rides.values), floorId: floorId, catIds: state.catIds, scale: catScale,
                            places: (0..<3).map(elevatorPlace))
            }
            .environment(\.walkingCats, Set(walks.keys).union(arrivingHere))
            // Cat frames are measured here, before the zoom: in the room's own points.
            .coordinateSpace(name: "roomContent")
            .scaleEffect(zoom.view.scale, anchor: .topLeading)
            .offset(x: zoom.view.offset.x, y: zoom.view.offset.y)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .environment(\.officeNight, night)
            if zoom.view.isZoomed {
                Text("1×").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: RoomZoom.pillSize.width, height: RoomZoom.pillSize.height)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(8)
                    .help("Show the whole room (or double-click)")
            }
            if let agent = hovered { CatCard(agent: agent, since: state.statusSince[agent.key]).padding(6) }
        }
        .frame(height: Self.height)
        .background(GeometryReader { proxy in
            Color.clear.onAppear { zoom.roomRect = proxy.frame(in: .named("office")) }
                .onChange(of: proxy.frame(in: .named("office"))) { _, rect in zoom.roomRect = rect }
                // Off screen (another tab): no room, so the cursor, clicks and scrolls there belong to that tab.
                .onDisappear { zoom.roomRect = .zero }
        })
        // Clicks only inside the visible room: the backdrop and cats extend past it, and took the tabs' clicks.
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onPreferenceChange(CatFramesKey.self) { catFrames = $0 }
        .onChange(of: zoom.tap?.at) { _, at in
            guard let tap = zoom.tap, let at, cat(at: tap.point) != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval) {
                // The first click of a double-click is a zoom, not a pat.
                if let double = zoom.lastDoubleClick, double >= at { return }
                state.playSound(.clicked)
            }
        }
        .onPreferenceChange(SceneFitKey.self) { fits.merge($0) { $1 } }
        .onPreferenceChange(CatFeetKey.self) { feet in
            shownFeet = feet
            startWalks(to: feet)
        }
        .onChange(of: seatKey, initial: true) { _, _ in updateSeating() }
        .onChange(of: floorKey, initial: true) { _, _ in noticeFloorChanges() }
        // A new building can leave every cat's floor id as it was (all in the Lounge): note it anyway, or the next
        // real move would be taken for a building swap and nobody would ride.
        .onChange(of: state.building.floors.map(\.id)) { _, _ in noticeFloorChanges() }
        // Rides are kept across a floor switch, so Follow moving to the arrival floor shows the arrival.
        .onChange(of: floorId) { _, _ in
            // A different floor: show the whole room and don't walk anyone across from the last floor.
            zoom.reset()
            walks = [:]
            lastFeet = [:]
        }
        // The simple room giving way to the built one (or back): its points mean something else, so nobody walks.
        .onChange(of: state.rooms[floorId] != nil) { _, _ in
            walks = [:]
            lastFeet = [:]
        }
        .task(id: catKey) { await WalkersLayer.preload(agents: state.office?.agents ?? [], catIds: state.catIds, art: state.art) }

    }

    /// A cat whose feet moved (status took it between desk and lounge) walks there, the way Cat Office walks.
    private func startWalks(to feet: [String: CatFeet]) {
        let now = Date()

        for (id, spot) in feet {
            let to = spot.point
            // Riding in: it walks out of the elevator once it has arrived, from where it appeared.
            if let ride = rides[id], ride.trip.to == floorId {
                // Once per ride (layout passes repeat), and only if this floor is still the one shown when it's out.
                guard walks[id] == nil, walkOuts[id] != ride.trip.start else { continue }
                walkOuts[id] = ride.trip.start
                let delay = max(0, ride.trip.doneTime.timeIntervalSince(now))
                let place = elevatorPlace(ride.waitIndex), placeFloor = elevatorFloorPoint(ride.waitIndex)
                let shownAt = floorId
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    walkOuts[id] = nil
                    guard floors.shown(state) == shownAt, rides[id]?.trip == ride.trip else { return }
                    let walk = CatWalk(id: id, agent: ride.agent, path: WalkRouter.path(from: place, fromFloor: placeFloor, to: to, toFloor: spot.floor, grid: state.navs[shownAt], frame: state.rooms[shownAt]?.frame, fit: fits[shownAt]), start: Date())
                    walks[id] = walk
                    state.playSound(.elevator)
                    DispatchQueue.main.asyncAfter(deadline: .now() + walk.duration + CatWalk.hop) {
                        if walks[id]?.start == walk.start { walks[id] = nil }
                    }
                }
                continue
            }
            // Riding out: the rider draws its walk to the elevator.
            if let ride = rides[id], ride.trip.from == floorId { continue }
            // Already on its way there: a new walk would restart it (and near a seat, step it off and on again).
            if walks[id]?.path.endsAt(to) == true { continue }
            // A cat stopped mid-walk starts from where it is (on the floor, unlifted); else from its spot.
            // (On or just onto a raised seat it starts from the floor under it, not the lifted point.)
            let midWalk = walks[id]?.floorPosition(at: now)
            guard let from = midWalk ?? lastFeet[id]?.point, hypot(to.x - from.x, to.y - from.y) > 12,
                  let agent = state.office?.agents.first(where: { $0.id == id }) else { continue }
            let fromFloor = midWalk == nil ? lastFeet[id]?.floor : nil
            let walk = CatWalk(id: id, agent: agent, path: WalkRouter.path(from: from, fromFloor: fromFloor, to: to, toFloor: spot.floor, grid: state.navs[floorId], frame: state.rooms[floorId]?.frame, fit: fits[floorId]), start: now)
            walks[id] = walk
            DispatchQueue.main.asyncAfter(deadline: .now() + walk.duration + CatWalk.hop) {
                if walks[id]?.start == walk.start { walks[id] = nil }
            }
        }
        // Remember where each cat last stood, also through a layout pass where it has no spot (it left the lounge
        // before its desk appeared) or Cat Office blips offline; forget cats that left the office.
        lastFeet.merge(feet) { $1 }
        let here = Set(floorCats.map(\.id))
        lastFeet = lastFeet.filter { here.contains($0.key) }
    }

    /// Changes when the cats in the office change (to preload their walks).
    private var catKey: String {
        (state.office?.agents ?? []).filter { $0.status != .ended }.map { CatPicker.cat(for: $0, catIds: state.catIds) }.sorted().joined(separator: ",")
    }

    private var floorId: Int { floors.shown(state) }
    /// Desks in two rows are drawn smaller; walking and riding cats match them.
    static let twoRowScale: CGFloat = 0.56
    /// Walking and riding cats' size: a built floor's scene cats, else the simple room's.
    private var catScale: CGFloat {
        if state.rooms[floorId] != nil { return fits[floorId].map { SceneCats.relative(catHeight: catHeight, fit: $0) } ?? 1 }
        return !floor.isLounge && floor.desks.count > 6 ? Self.twoRowScale : 1
    }
    private var catHeight: Double { state.building.catHeight ?? BuiltRoom.defaultCatHeight }

    /// The `index`th place cats wait for the elevator, in "roomContent": a built floor's real elevator (its door spot,
    /// Cat Office's waiting spread), else the simple room's door.
    private func elevatorPlace(_ index: Int) -> CGPoint {
        if let built = state.rooms[floorId], let fit = fits[floorId] {
            let door = built.elevator?.standAt ?? FloorPoint(u: 0.5, v: 0.5)
            let p = built.frame.px(ElevatorTrip.waitingPlace(door, index: index))
            if p.x.isFinite && p.y.isFinite { return fit.point(p) }
        }
        let door = ElevatorArt.door()
        return CGPoint(x: door.x + ElevatorTrip.waitingOffset(index: index), y: door.y)
    }

    /// The floor point of `elevatorPlace(index)` on a built floor (nil on the simple room).
    private func elevatorFloorPoint(_ index: Int) -> FloorPoint? {
        guard let built = state.rooms[floorId], fits[floorId] != nil else { return nil }
        return ElevatorTrip.waitingPlace(built.elevator?.standAt ?? FloorPoint(u: 0.5, v: 0.5), index: index)
    }

    /// The floor as seated on a built room: only the desks the room could place (unknown designs are skipped).
    private func seatFloor(_ built: BuiltRoom) -> Floor {
        let ids = Set(built.desks.map(\.id))
        var f = floor
        f.desks = floor.desks.filter { ids.contains($0.id) }
        return f
    }

    private func cast(_ built: BuiltRoom) -> SceneCast {
        let f = seatFloor(built)
        let seating = seatings[floorId] ?? FloorPlan.seating(on: f, agents: floorCats, previous: nil, seats: built.seats.count)
        return SceneCast(seating: seating, agents: floorCats, deskIds: f.desks.map(\.id), lounge: floor.isLounge,
                         mirrored: state.mirror.places(on: floorId, agents: state.office?.agents ?? [], in: state.building))
    }
    private var floor: Floor { state.building.floor(id: floorId) ?? Building.fallback.floors[0] }
    private var floorCats: [OfficeAgent] { FloorPlan.cats(on: floorId, agents: state.office?.agents ?? [], in: state.building, mirror: state.mirror) }
    /// Changes when who's on the shown floor, or their status or desk, changes.
    private var seatKey: String {
        let built = state.rooms[floorId].map { "built:\($0.seats.count):\($0.desks.map(\.id).joined(separator: "+"))" } ?? ""
        return "\(floorId)|\(built)|" + floorCats.map { "\($0.id):\($0.status.rawValue):\($0.desk?.id ?? "")" }.sorted().joined(separator: ",")
    }

    private func updateSeating() {
        if let built = state.rooms[floorId] {
            seatings[floorId] = FloorPlan.seating(on: seatFloor(built), agents: floorCats, previous: seatings[floorId], seats: built.seats.count)
        } else {
            seatings[floorId] = FloorPlan.seating(on: floor, agents: floorCats, previous: seatings[floorId])
        }
    }

    private func room() -> some View {
        let seating = seatings[floorId] ?? FloorPlan.seating(on: floor, agents: floorCats, previous: nil)
        let byId = Dictionary(floorCats.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return Group {
            if floor.isLounge {
                LoungeFloor(slots: seating.lounge.map { $0.flatMap { byId[$0] } }, overflow: seating.loungeOverflow,
                            nearby: seating.nearby.mapValues { $0.compactMap { byId[$0] } }, nearbyOverflow: seating.nearbyOverflow,
                            queued: seating.queue.count + seating.queueOverflow)
            } else {
                deskGrid(seating, byId)
            }
        }
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    /// The floor's own desks in rows of 6 (shrunk to fit two rows), helpers beside their parents, a queue at the right.
    private func deskGrid(_ seating: FloorSeating, _ byId: [String: OfficeAgent]) -> some View {
        let rows = stride(from: 0, to: floor.desks.count, by: 6).map { Array($0..<min($0 + 6, floor.desks.count)) }
        let twoRows = rows.count > 1
        return HStack(alignment: .bottom, spacing: 6) {
            // Two rows overlap a little (the back row's names tuck under the front row's desks), then shrink to fit.
            VStack(alignment: .leading, spacing: twoRows ? -24 : 2) {
                ForEach(rows, id: \.self) { row in
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(row, id: \.self) { i in
                            let seat = floor.desks[i]
                            if let id = seating.desks.indices.contains(i) ? seating.desks[i] : nil, let agent = byId[id] {
                                CatView(agent: agent, atDesk: true, seat: seat).catFrame(agent.id)
                                    .overlay(alignment: .bottomTrailing) {
                                        HStack(spacing: -6) {
                                            ForEach(seating.nearby[id] ?? [], id: \.self) { hid in
                                                if let helper = byId[hid] { NearbyHelper(agent: helper).catFrame(helper.id) }
                                            }
                                            if let more = seating.nearbyOverflow[id] { RoomPill(text: "+\(more)").fixedSize() }
                                        }
                                        // Beside the desk, clear of the parent's name pill.
                                        .offset(x: 22, y: -26)
                                    }
                            } else {
                                FreeDesk(seat: seat)
                            }
                        }
                    }
                }
                if floor.desks.isEmpty { RoomPill(text: "No desks on this floor") }
            }
            .scaleEffect(twoRows ? Self.twoRowScale : 1, anchor: .bottomLeading)
            // A scale doesn't shrink the layout: a fixed height keeps two rows from growing the room.
            .frame(height: twoRows ? Self.height - RoomBackdrop.wallHeight - 14 : nil, alignment: .bottomLeading)
            .padding(.leading, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !seating.queue.isEmpty {
                VStack(spacing: 2) {
                    ForEach(seating.queue, id: \.self) { id in
                        if let agent = byId[id] { NearbyHelper(agent: agent).catFrame(agent.id) }
                    }
                    if seating.queueOverflow > 0 { RoomPill(text: "+\(seating.queueOverflow)") }
                }
                .padding(.trailing, 10)
            }
        }
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

/// The floor's own wall and floor textures, its elevator, the Lounge sign, a plant and a lamp.
struct RoomBackdrop: View {
    let floor: Floor
    @EnvironmentObject var state: AppState
    @Environment(\.officeNight) private var officeNight

    /// The back wall's height and where the floor starts (the floor line).
    static let wallHeight: CGFloat = 46

    var body: some View {
        let night = officeNight
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                texture(floor.wallTexture?.image ?? "assets/room/walls/plaster.png", color: floor.wallTexture?.color ?? "#fdeee0")
                    .frame(height: Self.wallHeight).clipped()
                Rectangle().fill(Color(hex: 0x73503F)).frame(height: 3)
                texture(floor.floorTexture?.image ?? "assets/room/floors/birch.png", color: floor.floorTexture?.color ?? "#eadbc8")
                    .frame(maxHeight: .infinity)
            }
            .colorMultiply(night ? Night.room : .white)
            ElevatorArt(floor: floor).offset(x: ElevatorArt.leading, y: 0)
            if floor.hasLoungeSign {
                roomArt("assets/room/wall-items/sign-lounge.png", size: 512).frame(width: 43, height: 20)
                    .frame(maxWidth: .infinity).offset(y: 12)
                    .colorMultiply(night ? Night.furniture : .white)
            }
            roomArt("assets/room/props/tall-plant.png", size: 480).frame(height: 52).offset(x: ElevatorArt.leading + 64, y: 22)
                .colorMultiply(night ? Night.furniture : .white)
            if night { LampLight() }
            roomArt("assets/room/props/floor-lamp.png", size: 480).frame(height: 64)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 14).offset(y: 12)
                .colorMultiply(night ? Night.furniture : .white)
        }
    }

    /// A texture tiled at Retina scale, on its own colour until it loads.
    private func texture(_ path: String, color: String) -> some View {
        SpriteImage(key: path, fallback: nil, mode: .tile) { await state.art.image(path: path, maxPixelSize: 1024) }
            .background(Color(hexString: color))
    }

    private func roomArt(_ path: String, size: Int) -> some View {
        SpriteImage(key: path, fallback: nil, mode: .fit) { await state.art.image(path: path, maxPixelSize: size) }
    }
}

extension Color {
    /// "#rrggbb" (Cat Office's room-parts colours).
    init(hexString: String) {
        self.init(hex: UInt32(hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xEADBC8)
    }
}

/// The floor's elevator (Cat Office's wall item) standing on the floor line at the left of the back wall, with the
/// floor number on its plate (room-parts.json plate rect and colour; font 0.8 × plate height).
struct ElevatorArt: View {
    let floor: Floor
    @EnvironmentObject var state: AppState
    @Environment(\.officeNight) private var officeNight

    static let leading: CGFloat = 8
    static let height: CGFloat = 54

    /// Where riders wait and appear: in front of the door, on the floor.
    static func door() -> CGPoint { CGPoint(x: leading + 26, y: RoomBackdrop.wallHeight + 16) }

    var body: some View {
        if let art = floor.elevator {
            let k = Self.height / art.size.height
            SpriteImage(key: art.image, fallback: nil) { await state.art.image(path: art.image, maxPixelSize: 512) }
                .frame(width: art.size.width * k, height: Self.height)
                .overlay(alignment: .topLeading) {
                    if let plate = art.plate {
                        Text("\(floor.id)")
                            .font(.system(size: max(6, plate.height * k * 0.8), weight: .bold).monospacedDigit())
                            .foregroundStyle(Color(hex: 0x5B4636))
                            .frame(width: plate.width * k, height: plate.height * k)
                            .background(Color(hexString: art.plateColor ?? "#f4ece6"))
                            .offset(x: plate.minX * k, y: plate.minY * k)
                    }
                }
                .colorMultiply(officeNight ? Night.furniture : .white)
                // Standing on the floor line: its foot at the wall's base.
                .offset(y: RoomBackdrop.wallHeight + 3 - Self.height + 6)
        }
    }
}

/// The fallback Lounge (a floor without a usable room): ten seats in a row, then "+N asleep".
struct LoungeFloor: View {
    let slots: [OfficeAgent?]
    let overflow: Int
    /// Helpers still working for a cat asleep here: beside its seat, by parent id.
    var nearby: [String: [OfficeAgent]] = [:]
    var nearbyOverflow: [String: Int] = [:]
    /// Helpers whose parent has no seat here.
    var queued = 0
    @EnvironmentObject var state: AppState
    @Environment(\.officeNight) private var officeNight

    /// Feet points for the seats: one row across the room (the fallback has no furniture to sit on).
    static let spots: [CGPoint] = (0..<10).map { CGPoint(x: 50 + CGFloat($0) * 46, y: 150) }
    static let catWidth: CGFloat = 40

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(slots.prefix(Self.spots.count).enumerated()), id: \.offset) { i, agent in
                if let agent {
                    CatView(agent: agent, atDesk: false, width: Self.catWidth, plain: true)
                        .offset(x: Self.spots[i].x - Self.catWidth / 2, y: Self.spots[i].y - Self.catWidth * 0.95 * 0.9)
                }
            }
            ForEach(Array(slots.prefix(Self.spots.count).enumerated()), id: \.offset) { i, agent in
                if let agent {
                    ForEach(Array((nearby[agent.id] ?? []).enumerated()), id: \.element.id) { k, helper in
                        let r = Self.helperRect(spot: i, index: k)
                        NearbyHelper(agent: helper).offset(x: r.minX, y: r.minY)
                    }
                    if let more = nearbyOverflow[agent.id] {
                        let r = Self.helperRect(spot: i, index: nearby[agent.id]?.count ?? 0)
                        RoomPill(text: "+\(more)").fixedSize().offset(x: r.minX, y: r.midY)
                    }
                }
            }
            RoomPill(text: summary)
                .offset(x: 200, y: 4 + RoomBackdrop.wallHeight + 110)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GeometryReader { proxy in
            let origin = proxy.frame(in: .named("roomContent")).origin
            Color.clear
                .preference(key: CatFeetKey.self, value: feet(origin))
                .preference(key: CatFramesKey.self, value: frames(origin))
        })
    }

    private var summary: String {
        var text = overflow > 0 ? "lounge · \(slots.compactMap { $0 }.count + overflow) asleep" : "lounge"
        if queued > 0 { text += " · \(queued) helping" }
        return text
    }

    /// A helper standing beside the cat at `spot` (NearbyHelper's 40 × 42), the k-th one further right.
    static func helperRect(spot: Int, index k: Int) -> CGRect {
        CGRect(x: spots[spot].x + 10 + CGFloat(k) * 16, y: spots[spot].y - 40, width: 40, height: 42)
    }

    private func feet(_ o: CGPoint) -> [String: CatFeet] {
        var out: [String: CatFeet] = [:]
        for (i, a) in slots.prefix(Self.spots.count).enumerated() { if let a { out[a.id] = CatFeet(point: CGPoint(x: o.x + Self.spots[i].x, y: o.y + Self.spots[i].y)) } }
        return out
    }

    private func frames(_ o: CGPoint) -> [String: CatHit] {
        var out: [String: CatHit] = [:]
        let w = Self.catWidth, h = w * 0.95
        for (i, a) in slots.prefix(Self.spots.count).enumerated() {
            if let a { out[a.id] = CatHit(frame: CGRect(x: o.x + Self.spots[i].x - w / 2, y: o.y + Self.spots[i].y - h * 0.9, width: w, height: h)) }
            for (k, helper) in (a.flatMap { nearby[$0.id] } ?? []).enumerated() {
                out[helper.id] = CatHit(frame: Self.helperRect(spot: i, index: k).offsetBy(dx: o.x, dy: o.y))
            }
        }
        return out
    }
}

/// A cat riding the elevator between floors.
struct Rider: Equatable {
    let id: String
    let agent: OfficeAgent
    let trip: ElevatorTrip
    let walkIn: WalkPath?
    let waitIndex: Int
}

struct RidersLayer: View {
    let rides: [Rider]
    let floorId: Int
    let catIds: [String]
    var scale: CGFloat = 1
    /// Where cats wait for the shown floor's elevator (3 places, "roomContent").
    var places: [CGPoint] = []
    @EnvironmentObject var state: AppState
    @Environment(\.officeNight) private var officeNight

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: rides.isEmpty)) { context in
            ZStack(alignment: .topLeading) {
                ForEach(rides, id: \.id) { ride in rider(ride, now: context.date) }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func rider(_ ride: Rider, now: Date) -> some View {
        let place = places.isEmpty
            ? CGPoint(x: ElevatorArt.door().x + ElevatorTrip.waitingOffset(index: ride.waitIndex), y: ElevatorArt.door().y)
            : places[ride.waitIndex % places.count]
        switch (ride.trip.phase(at: now), ride.trip.from == floorId, ride.trip.to == floorId) {
        case (.walkingIn, true, _):
            let speed = WalkPath.speed(for: ride.id, base: CatWalk.baseSpeed)
            let d = CGFloat(now.timeIntervalSince(ride.trip.start)) * speed
            let path = ride.walkIn ?? WalkPath(from: place, to: place)
            sprite(ride, feet: path.position(atDistance: d), direction: path.direction(atDistance: d),
                   frame: WalkPath.frame(distance: d, stride: CatWalk.stride, phase: WalkPath.phase(for: ride.id)), alpha: 1)
        case (.boarding(let p), true, _):
            sprite(ride, feet: place, direction: "back-left", frame: 0, alpha: 1 - p)
        case (.arriving(let p), _, true):
            sprite(ride, feet: place, direction: "front-right", frame: 0, alpha: p)
        default:
            EmptyView()
        }
    }

    private func sprite(_ ride: Rider, feet: CGPoint, direction: String, frame: Int, alpha: Double) -> some View {
        let cat = CatPicker.cat(for: ride.agent, catIds: catIds)
        let s = DeskComposition.catScale * DeskStation.scale * scale
        return SpriteImage(key: "walk-\(cat)-\(direction)-\(frame)", fallback: Theme.color(ride.agent.status)) {
            await state.art.walkImage(cat: cat, direction: direction, frame: frame)
        }
        .frame(width: 360 * s, height: 380 * s)
        .colorMultiply(officeNight ? Night.furniture : .white)
        .opacity(alpha)
        .offset(x: feet.x - 180 * s, y: feet.y - 300 * s)
    }
}

/// Whether the office is drawn at night: ClaudeBar's appearance (the ☀️/🌙 setting; Auto follows the Mac).
private struct OfficeNightKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var officeNight: Bool {
        get { self[OfficeNightKey.self] }
        set { self[OfficeNightKey.self] = newValue }
    }
}

/// The night room's colours (dark mode).
enum Night {
    /// Multiplied into the walls and floor: deep evening blue.
    static let room = Color(red: 0.36, green: 0.42, blue: 0.66)
    /// Multiplied into furniture and desks: just cooled, still bright against the room.
    static let furniture = Color(red: 0.86, green: 0.88, blue: 0.96)
    /// Multiplied into sleeping cats: a little dimmer.
    static let asleep = Color(red: 0.78, green: 0.8, blue: 0.9)
    static let lamp = Color(red: 1, green: 0.83, blue: 0.54)
    static let screen = Color(red: 0.45, green: 0.75, blue: 1)
}

/// The floor lamp's warm light at night: a glow at the shade and a pool on the floor under it.
struct LampLight: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(RadialGradient(colors: [Night.lamp.opacity(0.9), Night.lamp.opacity(0)], center: .center, startRadius: 2, endRadius: 34))
                .frame(width: 68, height: 68)
                .offset(x: 6, y: -6)
            Ellipse()
                .fill(RadialGradient(colors: [Night.lamp.opacity(0.45), Night.lamp.opacity(0)], center: .center, startRadius: 4, endRadius: 80))
                .frame(width: 170, height: 70)
                .offset(x: 50, y: 52)
        }
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .padding(.trailing, 12)
        .offset(y: 8)
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}

/// A desk nobody is at: the floor's own desk design, dimmed.
struct FreeDesk: View {
    var seat: FloorDesk?
    @EnvironmentObject var state: AppState
    @Environment(\.officeNight) private var officeNight

    var body: some View {
        VStack(spacing: 1) {
            SpriteImage(key: "desk-\(seat?.design ?? "default")-\(seat?.rear ?? false)", fallback: nil) {
                await state.art.deskImage(id: seat?.design, rear: seat?.rear ?? false)
            }
            .frame(width: 60, height: 53)
            .scaleEffect(x: seat?.flip == true ? -1 : 1, y: 1)
            .colorMultiply(officeNight ? Night.furniture : .white)
            .opacity(0.75)
            .frame(width: 64, height: 64 * 1.34, alignment: .bottom)
            .padding(.bottom, 14)
            RoomPill(text: "free desk").opacity(0.6)
        }
    }
}

/// A helper with no free desk: standing beside its parent's desk, a little smaller ("working nearby").
struct NearbyHelper: View {
    let agent: OfficeAgent
    @EnvironmentObject var state: AppState
    @Environment(\.officeNight) private var officeNight

    var body: some View {
        let cat = CatPicker.cat(for: agent, catIds: state.catIds)
        SpriteImage(key: "\(cat)-standing-front-left", fallback: Theme.color(agent.status)) {
            await state.art.catImage(cat: cat, pose: .standing, direction: "front-left")
        }
        .frame(width: 40, height: 42)
        .colorMultiply(officeNight ? Night.furniture : .white)
        .help("\(agent.label) · working nearby")
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
                let f = state.building.floor(id: state.followFloor)
                Text("· \(f?.id ?? 1) \(f?.name ?? "Lounge")").font(.callout.weight(.semibold))
                if let office = state.office {
                    OfficeSummary(office: office, count: FloorPlan.cats(on: f?.id ?? 1, agents: office.agents, in: state.building, mirror: state.mirror).count)
                        .font(.callout)
                }
                Spacer(minLength: 6)
                MusicButton()
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

extension View {
    /// Reports a point (this view's own coordinates) as a cat's feet, in "roomContent".
    func catFeet(_ id: String, at point: CGPoint) -> some View {
        background(GeometryReader { proxy in
            let origin = proxy.frame(in: .named("roomContent")).origin
            Color.clear.preference(key: CatFeetKey.self, value: [id: CatFeet(point: CGPoint(x: origin.x + point.x, y: origin.y + point.y))])
        })
    }
}

private extension View {
    func catFrame(_ id: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: CatFramesKey.self, value: [id: CatHit(frame: proxy.frame(in: .named("roomContent")))])
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
    /// The floor's desk this cat sits at (its design, mirrored, turned).
    var seat: FloorDesk? = nil
    @EnvironmentObject var state: AppState
    @Environment(\.officeNight) private var officeNight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.walkingCats) private var walkingCats

    var body: some View {
        let cat = CatPicker.cat(for: agent, catIds: state.catIds)
        let scene = DeskScene(seated(agent))
        VStack(spacing: 1) {
            ZStack(alignment: .bottom) {
                if agent.status == .waiting && !plain && !atDesk {
                    // B's spotlight: a soft amber glow under a cat that needs you.
                    Ellipse()
                        .fill(RadialGradient(colors: [Theme.waiting.opacity(0.6), Theme.waiting.opacity(0)],
                                             center: .center, startRadius: 3, endRadius: 46))
                        .frame(width: 96, height: 30)
                        .offset(y: 10)
                }
                if !plain && !atDesk { StatusRing(status: agent.status, attention: false).scaleEffect(width / 64).offset(y: 3) }
                if atDesk {
                    DeskStation(agent: agent, cat: cat, scene: scene)
                } else {
                    animatedCat(cat, scene).opacity(walkingCats.contains(agent.id) ? 0 : 1)
                }
                if agent.status == .waiting && !atDesk {
                    Text("!").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 16, height: 16).background(Circle().fill(Color(hex: 0xE5484D)))
                        .offset(x: 18, y: -60)
                }
            }
            .frame(width: atDesk ? nil : width, height: plain ? width * 0.95 : (atDesk ? nil : width * 1.34))
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

    /// The agent as seated at this floor's desk (design, mirrored, turned), so DeskStation draws that desk.
    private func seated(_ agent: OfficeAgent) -> OfficeAgent {
        guard let seat else { return agent }
        var a = agent
        a.desk = AgentDesk(id: seat.design, flip: seat.flip, rear: seat.rear)
        return a
    }

    /// The cat's own desk in Cat Office (design, rear view, mirrored), else the default one.
    private func desk(_ scene: DeskScene) -> some View {
        SpriteImage(key: "desk-\(scene.deskId ?? "default")-\(scene.rear)", fallback: nil) {
            await state.art.deskImage(id: scene.deskId, rear: scene.rear)
        }
        .frame(width: 60, height: 53)
        .scaleEffect(x: scene.mirrored ? -1 : 1, y: 1)
        .colorMultiply(officeNight ? Night.furniture : .white)
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
                .colorMultiply(!officeNight ? .white : agent.status == .idle ? Night.asleep : Night.furniture)
                .scaleEffect(motion.scale, anchor: .bottom)
                .offset(y: motion.offsetY)
        }
    }
}

/// A cat at its desk, laid out the way Cat Office places them (DeskComposition): the desk's own design, mirrored
/// or turned as reported, the cat's feet on the desk's stand point, facing the screen; ring and glow at its feet.
struct DeskStation: View {
    let agent: OfficeAgent
    let cat: String
    let scene: DeskScene
    @EnvironmentObject var state: AppState
    @Environment(\.officeNight) private var officeNight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var geometry: DeskGeometry?
    @Environment(\.walkingCats) private var walkingCats

    /// Floor pixels to points: a desk about 60pt wide.
    static let scale: CGFloat = 0.22
    /// Cat Office's walnut desk, until the real geometry has loaded.
    static let fallback = DeskGeometry(width: 276, height: 242, anchor: CGPoint(x: 186.5, y: 239.2), stand: CGVector(dx: -110, dy: -20),
                                       rear: DeskGeometry.Sprite(width: 282, height: 228, anchor: CGPoint(x: 189.5, y: 223.7)))

    var body: some View {
        let k = Self.scale
        let c = DeskComposition(geometry ?? Self.fallback, flip: scene.mirrored, rear: scene.rear)
        let b = c.bounds
        let desk = place(c.desk, in: b)
        let catRect = place(c.cat, in: b)
        let feet = CGPoint(x: (c.cat.minX + 180 * DeskComposition.catScale - b.minX) * k,
                           y: (c.cat.minY + 300 * DeskComposition.catScale - b.minY) * k)
        ZStack(alignment: .topLeading) {
            if agent.status == .waiting {
                Ellipse()
                    .fill(RadialGradient(colors: [Theme.waiting.opacity(0.6), Theme.waiting.opacity(0)], center: .center, startRadius: 3, endRadius: 46))
                    .frame(width: 96, height: 30)
                    .offset(x: feet.x - 48, y: feet.y - 15)
            }
            StatusRing(status: agent.status, attention: false).scaleEffect(0.8).frame(width: 40, height: 10)
                .offset(x: feet.x - 20, y: feet.y - 5)
            if agent.status == .working && officeNight {
                Ellipse()
                    .fill(RadialGradient(colors: [Night.screen.opacity(0.55), Night.screen.opacity(0)], center: .center, startRadius: 2, endRadius: 40))
                    .frame(width: 80, height: 50)
                    .offset(x: desk.midX - 40, y: desk.minY - 6)
                    .blendMode(.screen)
            }
            let here = walkingCats.contains(agent.id) ? 0.0 : 1.0
            if c.catInFront {
                deskImage(desk)
                catImage(catRect).opacity(here)
            } else {
                catImage(catRect).opacity(here)
                deskImage(desk)
            }
            if agent.status == .waiting {
                Text("!").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 16, height: 16).background(Circle().fill(Color(hex: 0xE5484D)))
                    .offset(x: feet.x + 8, y: catRect.minY + 2)
            }
        }
        .frame(width: b.width * k, height: b.height * k, alignment: .topLeading)
        .catFeet(agent.id, at: feet)
        .task(id: scene.deskId) { geometry = await state.art.deskGeometry(id: scene.deskId) }
    }

    private func place(_ r: CGRect, in b: CGRect) -> CGRect {
        let k = Self.scale
        return CGRect(x: (r.minX - b.minX) * k, y: (r.minY - b.minY) * k, width: r.width * k, height: r.height * k)
    }

    private func deskImage(_ r: CGRect) -> some View {
        SpriteImage(key: "desk-\(scene.deskId ?? "default")-\(scene.rear)", fallback: nil) {
            await state.art.deskImage(id: scene.deskId, rear: scene.rear)
        }
        .frame(width: r.width, height: r.height)
        .scaleEffect(x: scene.mirrored ? -1 : 1, y: 1)
        .colorMultiply(officeNight ? Night.furniture : .white)
        .offset(x: r.minX, y: r.minY)
    }

    private func catImage(_ r: CGRect) -> some View {
        let pose = scene.pose, direction = scene.direction
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || agent.status == .waiting)) { context in
            let motion = reduceMotion ? CatMotion(offsetY: 0, scale: 1)
                : CatMotion.at(status: agent.status, time: context.date.timeIntervalSinceReferenceDate)
            SpriteImage(key: "\(cat)-\(pose.rawValue)-\(direction)", fallback: Theme.color(agent.status)) {
                await state.art.catImage(cat: cat, pose: pose, direction: direction)
            }
            .frame(width: r.width, height: r.height)
            .colorMultiply(officeNight ? Night.furniture : .white)
            .scaleEffect(motion.scale, anchor: .bottom)
            .offset(x: r.minX, y: r.minY + motion.offsetY)
        }
    }
}

/// One cat walking to its next spot.
struct CatWalk: Equatable {
    let id: String
    let agent: OfficeAgent
    let path: WalkPath
    let start: Date

    /// Cat Office's 190 floor px/s at ClaudeBar's scale (0.22 pt per px), twice as fast: a walk takes a few seconds.
    static let baseSpeed: CGFloat = 190 * DeskStation.scale * 2
    /// A walk frame every 22 floor px (Cat Office's STRIDE_PX), at ClaudeBar's scale.
    static let stride: CGFloat = 22 * DeskStation.scale
    /// The hop onto the spot on arrival (Cat Office: 0.18 sim min, a small arc).
    static let hop: TimeInterval = 0.18

    var speed: CGFloat { WalkPath.speed(for: id, base: Self.baseSpeed) }
    var duration: TimeInterval { TimeInterval(path.length / speed) }

    func distance(at now: Date) -> CGFloat { CGFloat(now.timeIntervalSince(start)) * speed }
    func position(at now: Date) -> CGPoint { path.position(atDistance: distance(at: now)) }
    /// Where it stands on the floor (under a raised seat while hopping on or off it): where a new walk starts.
    func floorPosition(at now: Date) -> CGPoint { path.floorPosition(atDistance: distance(at: now)) }
}

/// The walking cats, drawn over the room: walk frames by distance, feet on the path, a little hop on arrival.
struct WalkersLayer: View {
    /// Loads the cats' walk frames (4 directions × still + 4 steps) ahead, so a walk never starts invisible.
    @MainActor static func preload(agents: [OfficeAgent], catIds: [String], art: ArtCache) async {
        let cats = Set(agents.filter { $0.status != .ended }.map { CatPicker.cat(for: $0, catIds: catIds) })
        for cat in cats {
            for direction in ["front-left", "front-right", "back-left", "back-right"] {
                for frame in 0...4 {
                    let key = "walk-\(cat)-\(direction)-\(frame)"
                    guard SpriteImage.loaded[key] == nil, let data = await art.walkImage(cat: cat, direction: direction, frame: frame),
                          let image = NSImage(data: data) else { continue }
                    SpriteImage.loaded[key] = image
                }
            }
        }
    }

    let walks: [String: CatWalk]
    let catIds: [String]
    let legFrames: Bool
    /// The floor's cat size (smaller on two-row floors).
    var scale: CGFloat = 1
    @EnvironmentObject var state: AppState
    @Environment(\.officeNight) private var officeNight

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: walks.isEmpty)) { context in
            ZStack(alignment: .topLeading) {
                ForEach(Array(walks.values), id: \.id) { walk in
                    walker(walk, now: context.date)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func walker(_ walk: CatWalk, now: Date) -> some View {
        let cat = CatPicker.cat(for: walk.agent, catIds: catIds)
        let distance = walk.distance(at: now)
        let arrived = distance >= walk.path.length
        let direction = walk.path.direction(atDistance: min(distance, walk.path.length - 0.01))
        let frame = arrived || !legFrames ? 0 : WalkPath.frame(distance: distance, stride: CatWalk.stride, phase: WalkPath.phase(for: walk.id))
        let feet = walk.path.position(atDistance: distance)
        // The hop: a small arc once there.
        let hopT = arrived ? min(1, now.timeIntervalSince(walk.start) - walk.duration) / CatWalk.hop : 0
        let lift = arrived ? CGFloat(sin(Double.pi * max(0, min(1, hopT)))) * 2 : 0
        let s = DeskComposition.catScale * DeskStation.scale * scale
        let size = CGSize(width: 360 * s, height: 380 * s)
        return SpriteImage(key: "walk-\(cat)-\(direction)-\(frame)", fallback: Theme.color(walk.agent.status)) {
            await state.art.walkImage(cat: cat, direction: direction, frame: frame)
        }
        .frame(width: size.width, height: size.height)
        .colorMultiply(officeNight ? Night.furniture : .white)
        .offset(x: feet.x - 180 * s, y: feet.y - 300 * s - lift)
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
    /// stretch: the image over the whole frame (a room sprite redrawn over its own box).
    enum Mode { case fit, fill, tile, stretch }

    let key: String
    let fallback: Color?
    var mode: Mode = .fit
    let load: () async -> Data?
    @State private var image: NSImage?
    @State private var failed = false

    /// Images already loaded, by key: a reopened dropdown (or a fresh render) draws them at once, no flicker.
    @MainActor static var loaded: [String: NSImage] = [:]
    /// Bumped when Cat Office's art changed: each sprite loads again (showing its old picture meanwhile).
    @ObservedObject private var artGeneration = ArtGeneration.shared

    var body: some View {
        Group {
            if let image = image ?? Self.loaded[key] {
                switch mode {
                case .fit: Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                case .fill: Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                case .tile: Image(nsImage: image).resizable(resizingMode: .tile)
                case .stretch: Image(nsImage: image).resizable().interpolation(.high)
                }
            } else if failed, let fallback {
                Circle().fill(fallback.opacity(0.8)).frame(width: 22, height: 22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            } else {
                Color.clear
            }
        }
        .task(id: "\(key)#\(artGeneration.value)") {
            if Self.loaded[key] != nil { return }
            if let data = await load(), let loaded = NSImage(data: data) {
                // Tiles repeat at Retina scale (2 pixels per point), like Cat Office draws its floors.
                if mode == .tile, let rep = loaded.representations.first {
                    loaded.size = NSSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2)
                }
                image = loaded
                Self.loaded[key] = loaded
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
                // Plain words, as in the session list (the raw action is on the list row's hover).
                Text("Last: \(ActionSummary.calm(last, working: agent.status == .working))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(8)
        .frame(maxWidth: 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
