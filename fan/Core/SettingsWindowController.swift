//
//  SettingsWindowController.swift
//  SoloFan
//
//  Opens the settings window from AppKit (menu bar context menu, app reopen, etc.).
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private weak var viewModel: FanControlViewModel?

    private override init() {
        super.init()
    }

    func bind(viewModel: FanControlViewModel) {
        self.viewModel = viewModel
    }

  /// Presents the settings window, creating it on first use.
    func openSettings() {
        guard let viewModel else {
            print("SettingsWindowController: no view model bound")
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: SettingsWindowView(isOpen: .constant(true), viewModel: viewModel)
        )
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor

        let window = NSWindow(contentViewController: hosting)
        window.title = "SoloFan Settings"
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.setContentSize(NSSize(width: 920, height: 600))
        window.minSize = NSSize(width: 780, height: 520)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.toolbarStyle = .unifiedCompact

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
