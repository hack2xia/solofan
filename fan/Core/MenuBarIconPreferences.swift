//
//  MenuBarIconPreferences.swift
//  SoloFan
//
//  Persists whether the menu bar status item is hidden.
//

import Foundation

extension Notification.Name {
    /// Posted after the menu bar icon is shown or hidden (`object`: `Bool` — true when hidden).
    static let menuBarIconVisibilityChanged = Notification.Name("MenuBarIconVisibilityChanged")
}

/// UserDefaults-backed preference for menu bar icon visibility.
enum MenuBarIconPreferences {
    private static let hiddenKey = "hideMenuBarIcon"

    /// When true, the status item is removed from the menu bar until the user shows it again.
    static var isHidden: Bool {
        get { UserDefaults.standard.bool(forKey: hiddenKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: hiddenKey)
            NotificationCenter.default.post(name: .menuBarIconVisibilityChanged, object: newValue)
        }
    }
}
