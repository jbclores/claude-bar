// Sources/ClaudeBar/FloorSelection.swift
import ClaudeBarCore
import SwiftUI

/// The floor shown in one office view. The dropdown's can be picked; the peek's always follows.
@MainActor
final class FloorSelection: ObservableObject {
    @Published var choice = FloorChoice()
    let alwaysFollow: Bool
    /// Where the picker's ▲ / ▼ / Follow buttons are (window points from the top-left), so the click test hits exactly them.
    var targets: [String: CGRect] = [:]

    init(alwaysFollow: Bool = false) { self.alwaysFollow = alwaysFollow }

    func shown(_ state: AppState) -> Int {
        alwaysFollow ? state.followFloor : choice.shown(target: state.followFloor, floors: state.building.floors.map(\.id))
    }

    /// Follow comes back on each time the dropdown opens.
    func reopen() { choice.resumeFollow() }
}
