//
//  FanControlTests.swift
//  ffanTests
//
//  Created by mohamad on 11/1/2026.
//

import XCTest
@testable import SoloFan

@MainActor
final class FanControlTests: XCTestCase {
    
    private var defaults: UserDefaults!
    private let suiteName = "FanControlTests"
    
    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }
    
    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }
    
    /// A controller backed by the scratch suite. Without this the tests write
    /// through `UserDefaults.standard` in the app's own domain, leaving the
    /// user's SoloFan stuck in manual mode at the floor RPM after a test run.
    private func makeController() -> FanController {
        FanController(systemMonitor: SystemMonitor(), defaults: defaults)
    }
    
    func testControlModeEnum() {
        XCTAssertEqual(ControlMode.manual, ControlMode.manual)
        XCTAssertEqual(ControlMode.automatic, ControlMode.automatic)
        XCTAssertNotEqual(ControlMode.manual, ControlMode.automatic)
    }
    
    func testFanControllerInitialization() {
        let controller = makeController()

        // `mode` is restored from the user's persisted settings, so it is not an
        // invariant of `init` — only the speed clamps are.
        XCTAssertGreaterThanOrEqual(controller.manualSpeed, FanRPMBounds.absoluteWriteMinRPM)
        XCTAssertLessThanOrEqual(controller.manualSpeed, FanRPMBounds.absoluteWriteMaxRPM)
    }
    
    func testFanControllerManualSpeed() {
        let controller = makeController()
        // Speed edits only take effect in manual mode, and the mode is restored
        // from persisted settings.
        controller.setMode(.manual)
        
        controller.setManualSpeed(3000)
        XCTAssertEqual(controller.manualSpeed, 3000)
        
        // Test clamping (no SMC data yet → unified limits fall back to `FanRPMBounds`)
        controller.setManualSpeed(10000)
        XCTAssertLessThanOrEqual(controller.manualSpeed, FanRPMBounds.fallbackMaxWhenSMCUnreadable)
        
        controller.setManualSpeed(500)
        XCTAssertGreaterThanOrEqual(controller.manualSpeed, FanRPMBounds.fallbackMinWhenSMCUnreadable)
    }
    
    func testFanControllerModeSwitch() {
        let controller = makeController()
        
        controller.setMode(.automatic)
        XCTAssertEqual(controller.mode, .automatic)
        
        controller.setMode(.manual)
        XCTAssertEqual(controller.mode, .manual)
    }
    
    func testFanControlViewModelInitialization() {
        let viewModel = FanControlViewModel()
        
        XCTAssertNotNil(viewModel)
        XCTAssertEqual(viewModel.fanSpeeds.count, 0)
    }
    
    func testTemperatureColorCalculation() {
        let viewModel = FanControlViewModel()
        
        // Test with no temperature
        viewModel.cpuTemperature = nil
        viewModel.gpuTemperature = nil
        let color1 = viewModel.getTemperatureColor()
        XCTAssertEqual(color1, .gray)
        
        // Test cool temperature
        viewModel.cpuTemperature = 45.0
        let color2 = viewModel.getTemperatureColor()
        XCTAssertEqual(color2, .blue)
        
        // Test warm temperature
        viewModel.cpuTemperature = 65.0
        let color3 = viewModel.getTemperatureColor()
        XCTAssertEqual(color3, .yellow)
        
        // Test hot temperature (70–85°C band is orange; red starts at 85°C)
        viewModel.cpuTemperature = 75.0
        let color4 = viewModel.getTemperatureColor()
        XCTAssertEqual(color4, .orange)
        
        viewModel.cpuTemperature = 90.0
        let color5 = viewModel.getTemperatureColor()
        XCTAssertEqual(color5, .red)
    }
    
    func testMaxTemperatureCalculation() {
        let viewModel = FanControlViewModel()
        
        viewModel.cpuTemperature = 50.0
        viewModel.gpuTemperature = 60.0
        XCTAssertEqual(viewModel.getMaxTemperature(), 60.0)
        
        viewModel.cpuTemperature = 70.0
        viewModel.gpuTemperature = 65.0
        XCTAssertEqual(viewModel.getMaxTemperature(), 70.0)
    }
}
