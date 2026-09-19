//
//  FanCurveTests.swift
//  fanTests
//
//  Pure-function coverage for the auto-mode curve (extracted from
//  FanController.updateAutoControl). No SMC, no helper, no timers.
//

import XCTest
@testable import SoloFan

final class FanCurveTests: XCTestCase {

    private let floor = 1000
    private let ceiling = 6000

    // MARK: - unifiedTarget

    func testAtOrBelowThresholdSitsAtFloor() {
        XCTAssertEqual(
            FanCurve.unifiedTarget(temperature: 50, threshold: 60,
                                   aggressiveness: 1.5, floorRPM: floor, ceilingRPM: ceiling),
            floor)
        XCTAssertEqual(
            FanCurve.unifiedTarget(temperature: 60, threshold: 60,
                                   aggressiveness: 1.5, floorRPM: floor, ceilingRPM: ceiling),
            floor)
    }

    func testAtRampEndSitsAtCeiling() {
        XCTAssertEqual(
            FanCurve.unifiedTarget(temperature: 90, threshold: 60,
                                   aggressiveness: 1.5, floorRPM: floor, ceilingRPM: ceiling),
            ceiling)
        // Just below the ramp end: 87°C → ratio 0.9 → floor + 0.9·span.
        XCTAssertEqual(
            FanCurve.unifiedTarget(temperature: 87, threshold: 60,
                                   aggressiveness: 1.5, floorRPM: floor, ceilingRPM: ceiling),
            5500)
    }

    func testNeutralResponseFollowsTemperatureMidpoint() {
        // threshold 60, temp 75 → tempRatio 0.5 → floor + span/2.
        XCTAssertEqual(
            FanCurve.unifiedTarget(temperature: 75, threshold: 60,
                                   aggressiveness: 1.5, floorRPM: floor, ceilingRPM: ceiling),
            3500)
    }

    func testResponseEndpoints() {
        // response 0 → always floor; response 3 → always ceiling.
        XCTAssertEqual(
            FanCurve.unifiedTarget(temperature: 80, threshold: 60,
                                   aggressiveness: 0.0, floorRPM: floor, ceilingRPM: ceiling),
            floor)
        XCTAssertEqual(
            FanCurve.unifiedTarget(temperature: 50, threshold: 60,
                                   aggressiveness: 3.0, floorRPM: floor, ceilingRPM: ceiling),
            ceiling)
    }

    func testRampEndNotAfterRampStart() {
        // Degenerate configuration (threshold = 90 = ramp end): above the
        // threshold the curve must be at the ceiling, not divide by zero.
        XCTAssertEqual(
            FanCurve.unifiedTarget(temperature: 95, threshold: 90,
                                   aggressiveness: 1.5, floorRPM: floor, ceilingRPM: ceiling),
            ceiling)
    }

    func testCeilingBelowFloorResolvesToFloor() {
        // User set autoMaxSpeed below the hardware minimum: the floor wins
        // (historical behavior snapshot — changing this needs a product call).
        XCTAssertEqual(
            FanCurve.unifiedTarget(temperature: 80, threshold: 60,
                                   aggressiveness: 3.0, floorRPM: floor, ceilingRPM: 800),
            floor)
    }

    // MARK: - targets

    func testEmergencyDrivesEachFanToItsOwnMax() {
        let targets = FanCurve.targets(
            unified: 2000, temperature: FanRPMBounds.emergencyTemperature,
            fanMins: [1000, 1700], fanMaxs: [5297, 4905], ceilingRPM: 4500)
        // Bypasses the auto ceiling (4500) and the unified target entirely.
        XCTAssertEqual(targets, [5297, 4905])
    }

    func testPerFanClampRespectsOwnEnvelopeAndCeiling() {
        // unified 5000 exceeds the auto ceiling → capped at 4500 for both.
        XCTAssertEqual(
            FanCurve.targets(unified: 5000, temperature: 70,
                             fanMins: [1000, 1700], fanMaxs: [5297, 4905], ceilingRPM: 4500),
            [4500, 4500])
        // unified below fan 1's minimum → fan 1 stays at its floor.
        XCTAssertEqual(
            FanCurve.targets(unified: 1200, temperature: 70,
                             fanMins: [1000, 1700], fanMaxs: [5297, 4905], ceilingRPM: 4500),
            [1200, 1700])
    }

    // MARK: - shouldApply

    func testShouldApplyHysteresis() {
        // First apply ever.
        XCTAssertTrue(FanCurve.shouldApply(newRepresentative: 2100, lastApplied: 0, isEmergency: false))
        // Beyond the 50-RPM deadband.
        XCTAssertTrue(FanCurve.shouldApply(newRepresentative: 2100, lastApplied: 2000, isEmergency: false))
        // Inside the deadband → skip.
        XCTAssertFalse(FanCurve.shouldApply(newRepresentative: 2030, lastApplied: 2000, isEmergency: false))
        // Emergency is never deduped, even with an identical prior target.
        XCTAssertTrue(FanCurve.shouldApply(newRepresentative: 5297, lastApplied: 5297, isEmergency: true))
    }
}
