//
//  FanRPMBounds.swift
//  ffan
//
//  Central RPM limits for SMC reads, UI sliders, and writes.
//

import Foundation

/// Hardware fan RPM bounds used when SMC keys are missing or before telemetry arrives.
enum FanRPMBounds {
    /// Typical Intel MacBook Pro ceiling; used only as an absolute write clamp.
    static let absoluteWriteMaxRPM = 8000

    static let absoluteWriteMinRPM = 500

    /// When `F%dMn` cannot be read, assume a quiet floor consistent with prior app behavior.
    static let fallbackMinWhenSMCUnreadable = 1000

    /// When `F%dMx` cannot be read, avoid assuming Intel-class 6500 RPM (incorrect on Apple Silicon).
    static let fallbackMaxWhenSMCUnreadable = 5200

    /// Demo / placeholder data when SMC is unavailable.
    static let demoMaxRPM = 4800

    /// At or above this temperature, auto mode ignores `autoMaxSpeed` and drives
    /// every fan to its hardware max.
    static let emergencyTemperature: Double = 88
}
