// Sources/ClaudeBarCore/FloorPlan.swift
import CoreGraphics
import Foundation

/// Where cats go in Cat Office's building (src/world/floors.ts, MissionControl.tsx): idle → Lounge; working or
/// waiting → their project's floor (the most specific matching repo root), else the Desk pool; helpers → their
/// parent's floor.
public enum FloorPlan {
    public static func floorId(for agent: OfficeAgent, among agents: [OfficeAgent], in building: Building) -> Int? {
        guard agent.status != .ended else { return nil }
        if agent.isSubagent {
            if let parent = agents.first(where: { $0.name == agent.parentName && !$0.isSubagent && $0.status != .ended }) {
                return floorId(for: parent, among: agents, in: building)
            }
            return building.deskPool?.id ?? building.lounge?.id
        }
        if agent.status == .idle { return building.lounge?.id ?? building.floors.first?.id }
        let place = agent.repoRoot ?? agent.cwd
        let match = building.floors
            .filter { $0.repoRoot.map { Paths.isInside(place, $0) } ?? false }
            .max { ($0.repoRoot?.count ?? 0) < ($1.repoRoot?.count ?? 0) }
        return match?.id ?? building.deskPool?.id ?? building.lounge?.id
    }
}
