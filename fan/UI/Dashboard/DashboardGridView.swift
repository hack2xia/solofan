//
//  DashboardGridView.swift
//  SoloFan
//
//  Widget dashboard with layout-engine-driven drop targeting and visual row packing.
//

import SwiftUI

// MARK: - Drag state

private struct WidgetDragState: Equatable {
    var widgetID: UUID
    var sourceRowID: UUID
    var kind: DashboardWidgetKind
    var columnSpan: Int
    var location: CGPoint
    var grabOffset: CGSize
    var sourceSize: CGSize
}

// MARK: - Grid view

struct DashboardGridView: View {
    @ObservedObject var store: DashboardStore
    @ObservedObject var viewModel: FanControlViewModel
    @ObservedObject var battery: BatteryMonitor
    @Binding var isEditing: Bool

    @State private var galleryRowID: UUID?
    @State private var showGallery = false

    @State private var dragState: WidgetDragState?
    @State private var activeDropSlot: DropSlotID?

    @State private var widgetFrames: [UUID: CGRect] = [:]
    @State private var dropSlotFrames: [DropSlotID: CGRect] = [:]

    private let gridSpace: CoordinateSpace = .named("dashboardGrid")

    var body: some View {
        VStack(spacing: 14) {
            ForEach(store.layout.rows) { row in
                dashboardRow(row)
            }

            if isEditing {
                addRowButton
            }
        }
        .coordinateSpace(name: "dashboardGrid")
        .onPreferenceChange(WidgetFramePreferenceKey.self) { widgetFrames = $0 }
        .onPreferenceChange(DropSlotFramePreferenceKey.self) { dropSlotFrames = $0 }
        .overlay(alignment: .topLeading) {
            dragPreview
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: store.layout)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: activeDropSlot)
        .sheet(isPresented: $showGallery) {
            if let rowID = galleryRowID {
                WidgetGallerySheet(store: store, targetRowID: rowID, hasBattery: battery.hasBattery)
            }
        }
        .onChange(of: isEditing) { editing in
            if !editing {
                dragState = nil
                activeDropSlot = nil
            }
        }
    }

    // MARK: - Row

    private func dashboardRow(_ row: DashboardRow) -> some View {
        VStack(spacing: 4) {
            if isEditing {
                rowToolbar(row)
            }

            ForEach(DashboardLayoutEngine.renderSegments(for: row)) { segment in
                switch segment {
                case .dropZone(let index):
                    dropZone(row: row, index: index)
                case .widget(let widget):
                    widgetCell(widget, in: row)
                        .opacity(dragState?.widgetID == widget.id ? 0.15 : 1)
                case .pair(let left, let right):
                    HStack(spacing: 12) {
                        widgetCell(left, in: row)
                            .frame(maxWidth: .infinity)
                            .opacity(dragState?.widgetID == left.id ? 0.15 : 1)
                        widgetCell(right, in: row)
                            .frame(maxWidth: .infinity)
                            .opacity(dragState?.widgetID == right.id ? 0.15 : 1)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func dropZone(row: DashboardRow, index: Int) -> some View {
        if isEditing {
            let slot = DropSlotID(rowID: row.id, index: index)
            DashboardDropZone(slot: slot, isActive: activeDropSlot == slot)
        }
    }

    // MARK: - Widget cell

    private func widgetCell(_ widget: DashboardWidget, in row: DashboardRow) -> some View {
        let isDragging = dragState?.widgetID == widget.id

        return ZStack(alignment: .topTrailing) {
            DashboardWidgetView(
                widget: widget,
                viewModel: viewModel,
                battery: battery,
                isEditing: isEditing
            )

            if isEditing && !isDragging {
                WidgetRemoveBadge {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        store.removeWidget(id: widget.id)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .trackWidgetFrame(id: widget.id, in: gridSpace)
        .highPriorityGesture(isEditing ? dragGesture(for: widget, in: row) : nil)
    }

    // MARK: - Drag

    private func dragGesture(for widget: DashboardWidget, in row: DashboardRow) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: gridSpace)
            .onChanged { value in
                guard isEditing else { return }

                if dragState == nil {
                    let frame = widgetFrames[widget.id] ?? .zero
                    dragState = WidgetDragState(
                        widgetID: widget.id,
                        sourceRowID: row.id,
                        kind: widget.kind,
                        columnSpan: widget.columnSpan,
                        location: value.location,
                        grabOffset: CGSize(
                            width: value.startLocation.x - frame.minX,
                            height: value.startLocation.y - frame.minY
                        ),
                        sourceSize: frame.size == .zero ? CGSize(width: 148, height: 72) : frame.size
                    )
                } else {
                    dragState?.location = value.location
                }

                activeDropSlot = DashboardLayoutEngine.resolveDropSlot(
                    at: value.location,
                    slotFrames: dropSlotFrames,
                    excludingWidgetID: widget.id,
                    layout: store.layout
                )
            }
            .onEnded { _ in
                commitDrop()
            }
    }

    private func commitDrop() {
        defer {
            dragState = nil
            activeDropSlot = nil
        }

        guard let drag = dragState,
              let slot = activeDropSlot,
              !DashboardLayoutEngine.isNoOpDrop(
                slot: slot,
                draggedWidgetID: drag.widgetID,
                sourceRowID: drag.sourceRowID,
                layout: store.layout
              )
        else { return }

        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            store.applyDrop(widgetID: drag.widgetID, to: slot)
        }
    }

    // MARK: - Drag preview (uses measured source size)

    @ViewBuilder
    private var dragPreview: some View {
        if let drag = dragState {
            let widget = DashboardWidget(
                id: drag.widgetID,
                kind: drag.kind,
                columnSpan: drag.columnSpan
            )
            let origin = CGPoint(
                x: drag.location.x - drag.grabOffset.width,
                y: drag.location.y - drag.grabOffset.height
            )

            DashboardWidgetView(
                widget: widget,
                viewModel: viewModel,
                battery: battery,
                isEditing: true
            )
            .frame(width: drag.sourceSize.width, height: drag.sourceSize.height)
            .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
            .offset(x: origin.x, y: origin.y)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Toolbar

    private func rowToolbar(_ row: DashboardRow) -> some View {
        HStack(spacing: 8) {
            Menu {
                Button("1 Column") {
                    withAnimation { store.setRowColumns(rowID: row.id, columns: 1) }
                }
                Button("2 Columns") {
                    withAnimation { store.setRowColumns(rowID: row.id, columns: 2) }
                }
            } label: {
                Label("\(row.columns) col", systemImage: "square.grid.2x2")
                    .font(.system(size: 10, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Button {
                galleryRowID = row.id
                showGallery = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

            if store.layout.rows.count > 1 {
                Button {
                    withAnimation { store.removeRow(id: row.id) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var addRowButton: some View {
        Button {
            withAnimation { store.addRow(columns: 2) }
        } label: {
            Label("Add Row", systemImage: "plus.rectangle.on.rectangle")
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal)
    }
}
