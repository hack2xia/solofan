//
//  DashboardStoreTests.swift
//  fanTests
//

import XCTest
@testable import SoloFan

@MainActor
final class DashboardStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "DashboardStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultLayoutWithBattery() {
        let layout = DashboardStore.defaultLayout(hasBattery: true)
        XCTAssertTrue(layout.placedKinds.contains(.cpuTemperature))
        XCTAssertTrue(layout.placedKinds.contains(.powerOrSystem))
        XCTAssertTrue(layout.placedKinds.contains(.batteryInfo))
        XCTAssertFalse(layout.placedKinds.contains(.gpuTemperature))
    }

    func testDefaultLayoutDesktop() {
        let layout = DashboardStore.defaultLayout(hasBattery: false)
        XCTAssertTrue(layout.placedKinds.contains(.gpuTemperature))
        XCTAssertFalse(layout.placedKinds.contains(.batteryInfo))
    }

    func testEncodeDecodeRoundTrip() throws {
        var layout = DashboardStore.defaultLayout(hasBattery: true)
        layout.rows[0].widgets[0].id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(DashboardLayout.self, from: data)

        XCTAssertEqual(decoded, layout)
    }

    func testAddWidgetPreventsDuplicates() {
        defaults.set(nil, forKey: "dashboardLayout")
        let store = DashboardStore(defaults: defaults)
        guard let rowID = store.layout.rows.first?.id else {
            XCTFail("Expected default row")
            return
        }

        XCTAssertFalse(store.addWidget(.cpuTemperature, toRow: rowID))
    }

    func testAddAndRemoveWidget() {
        // Seed a known layout: `defaultLayout` depends on whether the machine
        // reports a battery, so starting from it makes this test machine-specific.
        let seed = DashboardLayout(rows: [
            DashboardRow(columns: 2, widgets: [DashboardWidget(kind: .cpuTemperature)])
        ])
        guard let seedData = try? JSONEncoder().encode(seed) else {
            XCTFail("Failed to encode seed layout")
            return
        }
        defaults.set(seedData, forKey: "dashboardLayout")
        let store = DashboardStore(defaults: defaults)

        store.addRow(columns: 2)
        guard let rowID = store.layout.rows.last?.id else {
            XCTFail("Expected new row")
            return
        }

        XCTAssertTrue(store.addWidget(.gpuTemperature, toRow: rowID))
        XCTAssertTrue(store.isKindPlaced(.gpuTemperature))

        let widgetID = store.layout.rows.last?.widgets.first?.id
        XCTAssertNotNil(widgetID)
        store.removeWidget(id: widgetID!)
        XCTAssertFalse(store.isKindPlaced(.gpuTemperature))
    }

    func testSetRowColumns() {
        defaults.removeObject(forKey: "dashboardLayout")
        let store = DashboardStore(defaults: defaults)
        guard let rowID = store.layout.rows.first?.id else { return }

        store.setRowColumns(rowID: rowID, columns: 1)
        XCTAssertEqual(store.layout.rows.first?.columns, 1)
    }

    func testApplyDropReordersWithinRow() {
        defaults.removeObject(forKey: "dashboardLayout")
        let store = DashboardStore(defaults: defaults)
        guard let row = store.layout.rows.first, row.widgets.count >= 2 else { return }

        let first = row.widgets[0]
        let second = row.widgets[1]
        store.applyDrop(widgetID: second.id, to: DropSlotID(rowID: row.id, index: 0))

        XCTAssertEqual(store.layout.rows.first?.widgets.first?.id, second.id)
        XCTAssertEqual(store.layout.rows.first?.widgets[1].id, first.id)
    }

    func testRenderSegmentsPairsHalfWidthWidgets() {
        let row = DashboardRow(columns: 2, widgets: [
            DashboardWidget(kind: .cpuTemperature),
            DashboardWidget(kind: .gpuTemperature)
        ])
        let segments = DashboardLayoutEngine.renderSegments(for: row)
        XCTAssertTrue(segments.contains { if case .pair = $0 { return true } else { return false } })
    }

    func testResolveDropSlotPicksNearest() {
        let rowID = UUID()
        let slot = DropSlotID(rowID: rowID, index: 1)
        let frames: [DropSlotID: CGRect] = [
            DropSlotID(rowID: rowID, index: 0): CGRect(x: 0, y: 0, width: 300, height: 12),
            slot: CGRect(x: 0, y: 80, width: 300, height: 12)
        ]
        let layout = DashboardLayout(rows: [
            DashboardRow(id: rowID, columns: 2, widgets: [
                DashboardWidget(kind: .cpuTemperature),
                DashboardWidget(kind: .gpuTemperature)
            ])
        ])
        let widgetID = layout.rows[0].widgets[0].id
        let resolved = DashboardLayoutEngine.resolveDropSlot(
            at: CGPoint(x: 150, y: 86),
            slotFrames: frames,
            excludingWidgetID: widgetID,
            layout: layout
        )
        XCTAssertEqual(resolved, slot)
    }

    func testDevicePowerProfileMapping() {
        let monitor = BatteryMonitor.shared
        if monitor.hasBattery {
            XCTAssertEqual(monitor.devicePowerProfile, .battery)
        } else {
            XCTAssertEqual(monitor.devicePowerProfile, .desktop)
        }
    }
}
