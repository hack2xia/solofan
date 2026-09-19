//
//  FanCurve.swift
//  SoloFan
//
//  Pure auto-mode curve math, extracted from FanController.updateAutoControl
//  so it can be unit-tested without SMC, the privileged helper, or timers.
//  No state, no I/O — everything arrives as parameters.
//

import Foundation

enum FanCurve {

    /// Unified auto target for a temperature reading. The threshold is the
    /// fan engagement point: at or below it the curve sits at the floor;
    /// above it the curve ramps linearly toward the ceiling at 90°C.
    /// `aggressiveness` (0…3) blends floor→curve→ceiling around the 1.5
    /// midpoint, matching the documented UI semantics.
    static func unifiedTarget(temperature: Double,
                              threshold: Double,
                              aggressiveness: Double,
                              floorRPM: Int,
                              ceilingRPM: Int) -> Int {
        let floor = Double(floorRPM)
        let ceiling = Double(ceilingRPM)
        let response = aggressiveness
        let midPoint = 1.5

        let rampStart = threshold
        let rampEnd = 90.0
        let tempRatio: Double
        if temperature <= rampStart {
            tempRatio = 0
        } else if rampEnd <= rampStart {
            tempRatio = 1
        } else {
            tempRatio = min(1.0, (temperature - rampStart) / (rampEnd - rampStart))
        }
        let tempBasedSpeed = floor + max(0, ceiling - floor) * tempRatio

        let targetSpeed: Double
        if response <= midPoint {
            let blend = response / midPoint
            targetSpeed = floor * (1.0 - blend) + tempBasedSpeed * blend
        } else {
            let blend = (response - midPoint) / (3.0 - midPoint)
            targetSpeed = tempBasedSpeed * (1.0 - blend) + ceiling * blend
        }

        // Deliberately `max(floor, …)`: if the user sets autoMaxSpeed below
        // the hardware minimum (ceiling < floor), the floor wins — preserved
        // historical behavior, do not "fix" without a product decision.
        return Int(max(floor, min(targetSpeed, ceiling)))
    }

    /// Per-fan targets. In a thermal emergency (≥ `FanRPMBounds.emergencyTemperature`)
    /// every fan is driven straight to its own hardware max, bypassing the
    /// unified target, the auto ceiling, and noise preferences entirely.
    /// `fanMins`/`fanMaxs` must already carry the controller's fallbacks for
    /// unreadable keys (see FanController.minRPM/maxRPM).
    static func targets(unified: Int,
                        temperature: Double,
                        fanMins: [Int],
                        fanMaxs: [Int],
                        ceilingRPM: Int) -> [Int] {
        fanMins.enumerated().map { index, mn in
            let mx = index < fanMaxs.count ? fanMaxs[index] : FanRPMBounds.fallbackMaxWhenSMCUnreadable
            if temperature >= FanRPMBounds.emergencyTemperature {
                return mx
            }
            return max(mn, min(unified, min(mx, ceilingRPM)))
        }
    }

    /// Auto-mode apply gating (hysteresis). An emergency target always
    /// applies — it must never be suppressed by the 50-RPM dedup, otherwise
    /// a first failed write would silence the emergency until unrelated
    /// state changes. `lastApplied == 0` means "nothing applied yet".
    static func shouldApply(newRepresentative: Int,
                            lastApplied: Int,
                            isEmergency: Bool) -> Bool {
        isEmergency || lastApplied == 0 || abs(newRepresentative - lastApplied) >= 50
    }
}
