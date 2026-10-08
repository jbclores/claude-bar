// scripts/room-fixtures.ts — run from a Cat Office folder: npx tsx <claude-bar>/scripts/room-fixtures.ts <in-dir> <out.json>
// Reads building.json, room-parts.json, props.json, desks.json (and wall-item-art.json) from <in-dir>, runs Cat Office's
// own room code on them, and writes what ClaudeBar's RoomGeometry must reproduce.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// Wrapped in an async main: tsx treats this file as CommonJS (claude-bar has no package.json "type"), so top-level await is unavailable.
async function main(): Promise<void> {
  const co = process.cwd();
  const [inDir, outFile] = process.argv.slice(2).map((p) => resolve(p));
  const load = (f: string) => JSON.parse(readFileSync(join(inDir, f), 'utf8'));
  const mod = (p: string) => import(pathToFileURL(join(co, p)).href);

  const { indexParts, roomWallHeight, wallItemSize, wallItemMirrored, wallItemImage, wallBase, wallLength, elevatorSpot } = await mod('src/world/room.ts');
  const { buildRoomOffice } = await mod('src/world/room-office.ts');
  const { alignShafts } = await mod('src/world/room-shaft.ts');
  const { snapRoomsToCells } = await mod('src/world/room-edit.ts');
  const { isBuiltRoom } = await mod('src/world/room-parts.ts');
  const { roomRugs, placeFixture } = await mod('src/world/room.ts');
  const { NavGrid } = await mod('src/world/nav-grid.ts');

  const building = load('building.json');
  const manifest = load('room-parts.json');
  const props = load('props.json');
  const desks = load('desks.json').desks;
  const parts = indexParts(manifest, props);

  let rooms: Record<number, unknown> = {};
  for (const f of building.floors) if (isBuiltRoom(f.room)) rooms[f.id] = f.room;
  const aligned = alignShafts(building, rooms, parts);
  const snapped = snapRoomsToCells(building, aligned.rooms, parts, desks);
  if (aligned.moved.length || snapped.moved.length) {
    console.error(`room-fixtures: Cat Office would move rooms on load (aligned ${aligned.moved}, snapped ${snapped.moved}); ClaudeBar uses stored values`);
    process.exit(2);
  }
  rooms = snapped.rooms;
  const office = buildRoomOffice(building, rooms, parts, desks);

  const r = (n: number) => Math.round(n * 1000) / 1000;
  const r6 = (n: number) => Math.round(n * 1e6) / 1e6;
  // Cat Office's Rect is {left, top, right, bottom}; the fixture schema wants width and height.
  const box = (q: { left: number; top: number; right: number; bottom: number }) => ({ left: r(q.left), top: r(q.top), width: r(q.right - q.left), height: r(q.bottom - q.top) });
  const out = { floors: [] as unknown[] };
  for (const floor of office.building.floors) {
    const room = rooms[floor.id] as any;
    const built = office.rooms[floor.id];
    if (!room || !built) continue;
    const { top, left, right } = floor.corners;
    const eu = Math.hypot(left.x - top.x, left.y - top.y), ev = Math.hypot(right.x - top.x, right.y - top.y);
    const size = (eu + ev) / 2;
    const wallHeight = roomWallHeight(parts, floor.id, room);
    const wall = (side: 'left' | 'right') => {
      const { from, to } = wallBase(floor, side);
      const start = side === 'left' ? to : from, end = side === 'left' ? from : to;
      const length = wallLength(floor, side);
      return { length: r(length), a: r6((end.x - start.x) / length), b: r6((end.y - start.y) / length), e: r(start.x), f: r(start.y - wallHeight) };
    };
    // RoomShell.tsx Rug (97-119): box in floor-plane px.
    const rugs = roomRugs(floor, room, parts).map((g: any) => {
      const def = parts.rugs.get(g.rug);
      return { id: g.id, rug: g.rug, image: def?.image ?? null, left: r((g.v - g.w / 2) * size), top: r((g.u - g.d / 2) * size), width: r(g.w * size), height: r(g.d * size), turned: !!g.turned };
    });
    // RoomShell.tsx WallItem (269-333): box in the wall frame; plate 315-330.
    const wallItems = room.wallItems.flatMap((item: any) => {
      const def = parts.wallItems.get(item.item);
      if (!def || def.mount === 'sprite') return [];
      const len = wallLength(floor, item.wall);
      const { width, height, bottom } = wallItemSize(def, item, wallHeight);
      const mirrored = wallItemMirrored(item, def);
      const x = (item.wall === 'left' ? 1 - item.at : item.at) * len;
      const left0 = x - width / 2, top0 = bottom - height;
      const plate = def.plate && def.image ? {
        left: r(left0 + (mirrored ? width - def.plate.x - def.plate.width : def.plate.x)), top: r(top0 + def.plate.y),
        width: r(def.plate.width), height: r(def.plate.height) } : null;
      return [{ id: item.id, item: item.item, wall: item.wall, image: wallItemImage(item, def) ?? null, mirrored, left: r(left0), top: r(top0), width: r(width), height: r(height), plate }];
    });
    const elevators = built.elevators.map((e: any) => {
      const s = elevatorSpot(floor, e.item, e.def);
      return { id: e.item.id, standAt: { u: r6(s.standAt.u), v: r6(s.standAt.v) }, facing: s.facing };
    });
    const fixtures = built.fixtures.map((x: any) => ({ id: x.item.id, image: x.image ?? null, mirrored: !!x.mirrored, ...box(x.rect), z: x.box.z }));
    const placedDesks = (office.desks[floor.id] ?? []).map((d: any) => ({
      id: d.placement.id, desk: d.placement.desk, image: d.sprite.image, flip: d.placement.flip, rear: d.rear,
      ...box(d.rect), z: d.box.z,
      standAt: { u: r6(d.standAt.u), v: r6(d.standAt.v) }, facing: d.facing }));
    const placedProps = built.props.map((p: any) => ({
      id: p.placement.id, prop: p.placement.prop, image: p.sprite?.image ?? null, mirrored: p.mirrored,
      ...box(p.rect), z: p.box.z, companionOf: p.companionOf ?? null,
      spots: p.spots.map((s: any) => ({ id: s.id, kind: s.kind, pose: s.pose ?? null, u: r6(s.standAt.u), v: r6(s.standAt.v), facing: s.facing, lift: s.lift ?? 0 })) }));
    // The floor the browser walks: SimulationEngine.indexFloors builds `new NavGrid(floor)` from the building that
    // buildRoomOffice returns (RoomSimulator.tsx:218), whose floors already have props and desks carved into the grid.
    const floorOut: any = { id: floor.id, corners: floor.corners, wallHeight, eu: r(eu), ev: r(ev),
      floorPlane: { size: r(size), a: r6((right.x - top.x) / size), b: r6((right.y - top.y) / size), c: r6((left.x - top.x) / size), d: r6((left.y - top.y) / size), e: top.x, f: top.y },
      walls: { left: wall('left'), right: wall('right') }, rugs, wallItems, elevators, fixtures, desks: placedDesks, props: placedProps };
    if (floor.grid) {
      const walkFloor = floor;
      const placedDesksForWalk = office.desks[floor.id] ?? [];
      const nav = new NavGrid(walkFloor);
      const pts: { u: number; v: number }[] = [];
      const elevator = walkFloor.spots.find((s: any) => s.kind === 'elevator');
      if (elevator) pts.push(elevator.standAt);
      for (const d of placedDesksForWalk) pts.push(d.standAt);
      for (const s of walkFloor.spots) if (s.kind !== 'elevator' && s.standAt) pts.push(s.standAt);
      // Plus fixed probes across the floor (some on open floor, some on furniture), the same for every floor.
      for (const [u, v] of [[0.1, 0.1], [0.5, 0.5], [0.9, 0.9], [0.2, 0.8], [0.8, 0.2], [0.33, 0.66]]) pts.push({ u, v });
      const routes: unknown[] = [];
      for (let i = 0; i < pts.length; i++) {
        for (let j = 0; j < pts.length; j++) {
          if (i === j) continue;
          // Every pair from/to the elevator, else a fixed sample: pairs (i, i+1), (i, i+3), (i, i+7) mod n.
          const n = pts.length;
          const sampled = i === 0 || j === 0 || j === (i + 1) % n || j === (i + 3) % n || j === (i + 7) % n;
          if (!sampled) continue;
          const path = nav.findPath(pts[i], pts[j]);
          routes.push({ from: { u: r6(pts[i].u), v: r6(pts[i].v) }, to: { u: r6(pts[j].u), v: r6(pts[j].v) },
                        path: path ? path.map((p: any) => ({ u: r6(p.u), v: r6(p.v) })) : null });
        }
      }
      floorOut.nav = { size: walkFloor.grid.size, walkable: walkFloor.grid.walkable, routes };
    }
    out.floors.push(floorOut);
  }
  writeFileSync(outFile, JSON.stringify(out, null, 1));
  console.log(`room-fixtures: ${out.floors.length} floors → ${outFile}`);
}
main();
