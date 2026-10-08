// scripts/sim-fixtures.ts — run from a Cat Office folder: npx tsx <claude-bar>/scripts/sim-fixtures.ts <in-dir> <out.json>
// Reads building.json, room-parts.json, props.json, desks.json and cats.json from <in-dir>, runs Cat Office's own
// simulation code (Rng, ACTIVITIES/activityFor, DECAY/decayNeeds, chooseActivity, createRoster) with fixed seeds, and
// writes what ClaudeBar's simulation port must reproduce.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// Wrapped in an async main: tsx treats this file as CommonJS (claude-bar has no package.json "type"), so top-level await is unavailable.
async function main(): Promise<void> {
  const co = process.cwd();
  const [inDir, outFile] = process.argv.slice(2).map((p) => resolve(p));
  const load = (f: string) => JSON.parse(readFileSync(join(inDir, f), 'utf8'));
  const mod = (p: string) => import(pathToFileURL(join(co, p)).href);

  const { indexParts } = await mod('src/world/room.ts');
  const { buildRoomOffice } = await mod('src/world/room-office.ts');
  const { alignShafts } = await mod('src/world/room-shaft.ts');
  const { snapRoomsToCells } = await mod('src/world/room-edit.ts');
  const { isBuiltRoom } = await mod('src/world/room-parts.ts');
  const { Rng } = await mod('src/simulation/rng.ts');
  const { ACTIVITIES, activityFor } = await mod('src/simulation/activities.ts');
  const { chooseActivity } = await mod('src/simulation/decision-engine.ts');
  const { createRoster } = await mod('src/agents/agent.registry.ts');
  const { NEED_KEYS } = await mod('src/agents/agent.types.ts');

  const building = load('building.json');
  const manifest = load('room-parts.json');
  const props = load('props.json');
  const desks = load('desks.json').desks;
  const cats = load('cats.json');
  const parts = indexParts(manifest, props);

  let rooms: Record<number, unknown> = {};
  for (const f of building.floors) if (isBuiltRoom(f.room)) rooms[f.id] = f.room;
  const aligned = alignShafts(building, rooms, parts);
  const snapped = snapRoomsToCells(building, aligned.rooms, parts, desks);
  if (aligned.moved.length || snapped.moved.length) {
    console.error(`sim-fixtures: Cat Office would move rooms on load (aligned ${aligned.moved}, snapped ${snapped.moved}); ClaudeBar uses stored values`);
    process.exit(2);
  }
  rooms = snapped.rooms;
  // The floors the browser walks: SimulationEngine takes the building buildRoomOffice returns (RoomSimulator.tsx:218).
  const walk = buildRoomOffice(building, rooms, parts, desks).building;

  const r6 = (n: number) => Math.round(n * 1e6) / 1e6;
  const seeds = [1, 2, 3, 42, 20261001];

  // rng: 50 nexts, then (same stream continued) 20 range(0, 0.15).
  const rng = seeds.map((seed) => {
    const g = new Rng(seed);
    const values: number[] = [];
    for (let i = 0; i < 50; i++) values.push(g.next());
    for (let i = 0; i < 20; i++) values.push(g.range(0, 0.15));
    return { seed, values };
  });

  // activities: every kind, plus what activityFor makes of a spot pose that changes it.
  const act = (d: any) => ({ kind: d.kind, label: d.label, icon: d.icon, verb: d.verb, state: d.state, gesture: d.gesture,
    expression: d.expression, arrival: d.arrival ?? null, duration: d.duration, gains: d.gains, lounge: d.lounge, asleep: !!d.asleep });
  const activities = Object.values(ACTIVITIES).map(act);
  const poseVariants: unknown[] = [];
  for (const kind of Object.keys(ACTIVITIES)) {
    for (const pose of ['stand', 'sit', 'sleep', 'type', null]) {
      poseVariants.push({ kind, pose, activity: act(activityFor({ kind, pose: pose ?? undefined })) });
    }
  }

  // decay: DECAY and decayNeeds are private to simulation-engine.ts (module const DECAY; method decayNeeds), so this
  // restates them verbatim (simulation-engine.ts:153, 1100-1108) rather than importing them.
  const DECAY: Record<string, number> = { energy: 0.14, thirst: 0.2, hunger: 0.12, social: 0.15, fun: 0.15 };
  const clampNeed = (x: number) => Math.min(100, Math.max(0, x));
  const decay = (state: string, needs0: Record<string, number>, minutes: number) => {
    const needs = { ...needs0 };
    const steps = Math.round(minutes * 30); // STEP = 1/30 sim minute
    for (let s = 0; s < steps; s++) {
      for (const key of NEED_KEYS) {
        let rate = DECAY[key];
        if (state === 'working' && (key === 'energy' || key === 'fun')) rate *= 1.3;
        if (state === 'resting' && key === 'energy') rate = 0;
        if (state === 'talking' && key === 'social') rate = 0;
        needs[key] = clampNeed(needs[key] - rate * (1 / 30));
      }
    }
    return needs;
  };
  const needsSets: Record<string, number>[] = [];
  const all = (v: number) => Object.fromEntries(NEED_KEYS.map((k: string) => [k, v]));
  needsSets.push(all(50));
  for (const k of NEED_KEYS) needsSets.push({ ...all(50), [k]: 5 });
  needsSets.push(all(5));
  const decaySets = [...needsSets, { energy: 100, thirst: 100, hunger: 100, social: 100, fun: 100 }, { energy: 3, thirst: 1, hunger: 0.5, social: 2, fun: 0 }];
  const decayOut: unknown[] = [];
  for (const state of ['idle', 'walking', 'working', 'talking', 'resting', 'celebrating']) {
    for (const needs0 of decaySets) {
      for (const minutes of [1, 10, 60, 600]) decayOut.push({ state, needs0, minutes, needs: decay(state, needs0, minutes) });
    }
  }

  // choices: chooseActivity from each (seed, floor, position, needs, minutesSinceWork). isFree/canReach accept every spot
  // (the engine's occupancy and reachability are separate), so a null needs `free: 'none'`.
  const byId = new Map<number, any>(walk.floors.map((f: any) => [f.id, f]));
  const floorIds = [1, 2, 12];
  for (const id of floorIds) if (!byId.has(id)) { console.error(`sim-fixtures: no floor ${id} in the building`); process.exit(2); }
  const positionsOf = (f: any) => {
    const d = f.spots.find((s: any) => s.kind === 'desk')?.standAt ?? { u: 0.2, v: 0.2 };
    return [{ u: 0.5, v: 0.5 }, d];
  };
  const firstSpot = (f: any, kind: string) => f.spots.find((s: any) => s.kind === kind)?.id ?? null;
  const choices: unknown[] = [];
  for (const seed of seeds) {
    for (const floorId of floorIds) {
      const f = byId.get(floorId);
      for (const position of positionsOf(f)) {
        for (const needs of needsSets) {
          for (const minutesSinceWork of [5, 80]) {
            // (lastSpotId, ownDeskId, free): the plain hot-desking cat, then a cat with a desk that last used a spot.
            const variants: [string | null, string | null, 'all' | 'none'][] = [[null, null, 'all']];
            variants.push([firstSpot(f, 'coffee') ?? firstSpot(f, 'sofa'), firstSpot(f, 'desk'), 'all']);
            if (minutesSinceWork === 5 && needs === needsSets[0]) variants.push([null, null, 'none']);
            for (const [lastSpotId, ownDeskId, free] of variants) {
              const choice = chooseActivity({ building: walk, rng: new Rng(seed), floorId, position, needs, minutesSinceWork,
                lastSpotId, ownDeskId, isFree: () => free === 'all', canReach: () => true });
              choices.push({ seed, floorId, position: { u: r6(position.u), v: r6(position.v) }, needs, minutesSinceWork,
                lastSpotId, ownDeskId, free,
                choice: choice ? { floor: choice.floor.id, spotId: choice.spot.id, kind: choice.def.kind } : null });
            }
          }
        }
      }
    }
  }

  // roster: createRoster on the walked building and cats.json.
  const roster = createRoster(walk, cats).map((s: any) => ({ id: s.id, name: s.name, role: s.role, catId: s.catId,
    deskFloor: s.desk?.floor ?? null, deskSpotId: s.desk?.spot.id ?? null, floor: s.floor }));

  // spots: every walked floor's spots exactly as the browser has them (buildRoomFloor's optional-spot filter, resolveOffice's
  // desk spots, closeSpots), in order.
  const spotOut = (s: any) => ({ id: s.id, kind: s.kind, pose: s.pose ?? null, u: s.standAt.u, v: s.standAt.v,
    slots: (s.slots ?? []).map((q: any) => ({ u: q.u, v: q.v })) });
  const floorSpots = (b: any) => b.floors.map((f: any) => ({ floor: f.id, spots: f.spots.map(spotOut) }));
  const spots = floorSpots(walk);

  // spotCases: the user building with pieces added that make closeSpots act (it acts on nothing in the stored building):
  // a trash bin on the water cooler's stand point (the spot moves to a free cell beside it) and a desk on an optional
  // plant spot (the spot closes). Each piece is placed so its footprint's middle is on the spot.
  const walkWith = (add: { floor: number; props: any[]; desks: any[] }) => {
    const b = JSON.parse(JSON.stringify(building));
    const f = b.floors.find((x: any) => x.id === add.floor);
    f.room.props.push(...add.props);
    f.room.desks.push(...add.desks);
    const rs: Record<number, unknown> = {};
    for (const x of b.floors) if (isBuiltRoom(x.room)) rs[x.id] = x.room;
    return buildRoomOffice(b, rs, parts, desks);
  };
  const spotOf = (floorId: number, id: string) => byId.get(floorId).spots.find((s: any) => s.id === id);
  const r6p = (p: { u: number; v: number }) => ({ u: r6(p.u), v: r6(p.v) });
  const water = spotOf(2, 'water-2').standAt;
  const trial = walkWith({ floor: 2, props: [{ id: 'test-bin', prop: 'trash-bin-pedal', u: 0.5, v: 0.5, facing: 0 }], desks: [] });
  const binFp = trial.rooms[2].props.find((p: any) => p.placement.id === 'test-bin').footprint;
  const bin = { id: 'test-bin', prop: 'trash-bin-pedal', ...r6p({ u: water.u + (binFp.u1 - binFp.u0) / 2, v: water.v + (binFp.v1 - binFp.v0) / 2 }), facing: 0 };
  const plant = spotOf(2, 'plant-2-3').standAt;
  const trialDesk = walkWith({ floor: 2, props: [], desks: [{ id: 'test-desk', desk: 's1-walnut', u: 0.5, v: 0.5, flip: false }] });
  const deskFp = trialDesk.desks[2].find((d: any) => d.placement.id === 'test-desk').footprint;
  const desk = { id: 'test-desk', desk: 's1-walnut', ...r6p({ u: plant.u + (deskFp.u1 - deskFp.u0) / 2, v: plant.v + (deskFp.v1 - deskFp.v0) / 2 }), flip: false };
  const spotCases = [
    { name: 'bin on the water cooler', add: { floor: 2, props: [bin], desks: [] } },
    { name: 'desk on a plant spot', add: { floor: 2, props: [], desks: [desk] } },
  ].map((c) => {
    const f = walkWith(c.add).building.floors.find((x: any) => x.id === 2);
    return { ...c, spots: f.spots.map(spotOut) };
  });
  const before = JSON.stringify(spots.find((f: any) => f.floor === 2).spots);
  for (const c of spotCases) {
    const ids = c.spots.map((s: any) => s.id);
    const moved = c.spots.find((s: any) => s.id === 'water-2');
    const ok = c.name.startsWith('bin') ? moved && (moved.u !== water.u || moved.v !== water.v) : !ids.includes('plant-2-3');
    if (!ok || JSON.stringify(c.spots) === before) { console.error(`sim-fixtures: spot case "${c.name}" did not make closeSpots act`); process.exit(2); }
  }

  const out = { activities, poseVariants, rng, decay: decayOut, choices, roster, spots, spotCases };
  writeFileSync(outFile, JSON.stringify(out, null, 1));
  const nulls = (choices as any[]).filter((c) => c.choice === null).length;
  const nSpots = spots.reduce((a: number, f: any) => a + f.spots.length, 0);
  console.log(`sim-fixtures: ${activities.length} activities, ${rng.length} rng seeds, ${decayOut.length} decay, ${choices.length} choices (${nulls} null), ${roster.length} cats, ${nSpots} spots, ${spotCases.length} spot cases → ${outFile}`);
}
main();
