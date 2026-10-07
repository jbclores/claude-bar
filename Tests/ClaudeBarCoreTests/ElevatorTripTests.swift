// Tests/ClaudeBarCoreTests/ElevatorTripTests.swift
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct ElevatorTripTests {
    let t0 = Date(timeIntervalSince1970: 1_791_300_000)

    @Test func rideTakesBasePlusPerFloor() {
        #expect(ElevatorTrip.rideTime(floors: 1) == 0.7 + 0.35)
        #expect(abs(ElevatorTrip.rideTime(floors: 11) - (0.7 + 0.35 * 11)) < 1e-9)
    }

    @Test func phasesRunWalkBoardRideArrive() {
        let trip = ElevatorTrip(from: 12, to: 1, start: t0, walkIn: 2)
        #expect(trip.phase(at: t0 + 1) == .walkingIn(0.5))
        if case .boarding(let p) = trip.phase(at: t0 + 2 + 0.175) { #expect(abs(p - 0.5) < 1e-6) } else { Issue.record("not boarding") }
        #expect(trip.phase(at: t0 + 2 + 0.35 + 1) == .riding)
        let ride = ElevatorTrip.rideTime(floors: 11)
        #expect(trip.arrivalTime == t0 + 2 + 0.35 + ride)
        if case .arriving(let p) = trip.phase(at: trip.arrivalTime + 0.175) { #expect(abs(p - 0.5) < 1e-6) } else { Issue.record("not arriving") }
        #expect(trip.phase(at: trip.doneTime + 0.01) == .arrived)
    }

    @Test func waitingCatsStandInThreePlaces() {
        #expect([0, 1, 2, 3].map(ElevatorTrip.waitingOffset) == [-12, 0, 12, -12])
    }
}

@Suite struct ElevatorWaitingPlaceTests {
    /// room.ts ELEVATOR_WAIT_SPREAD (0.014, 0.035), k = (index % 3) - 1 (simulation-engine.ts elevatorPoint).
    @Test func waitingPlacesSpreadAlongTheFloor() {
        let door = FloorPoint(u: 0.5, v: 0.1)
        let places = [0, 1, 2, 3].map { ElevatorTrip.waitingPlace(door, index: $0) }
        #expect(abs(places[0].u - 0.486) < 1e-9 && abs(places[0].v - 0.065) < 1e-9)
        #expect(places[1] == door)
        #expect(abs(places[2].u - 0.514) < 1e-9 && abs(places[2].v - 0.135) < 1e-9)
        #expect(places[3] == places[0])
    }
}
