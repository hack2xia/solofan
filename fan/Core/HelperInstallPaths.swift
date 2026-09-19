//
//  HelperInstallPaths.swift
//  SoloFan
//
//  Single source of truth for the privileged helper's install locations and
//  the sudoers rule. The shell installers (tools/smc-helper/install.sh and
//  scripts/install.sh) duplicate these values — they cannot import Swift —
//  so any change here must be mirrored there (both carry a pointer comment).
//

import Foundation

enum HelperInstallPaths {
    /// Where the root helper binary is installed.
    static let helper = "/usr/local/bin/smc-helper"

    /// NOPASSWD drop-in authorizing exactly the helper path above.
    static let sudoersDropIn = "/etc/sudoers.d/smc-fan-helper"

    /// The full drop-in contents (trailing newline included).
    static let sudoersRule = "%admin ALL=(root) NOPASSWD: \(helper)\n"

    /// Validator run after writing the drop-in; a malformed drop-in can break
    /// sudo system-wide, so the write is rolled back if this fails.
    static let visudo = "/usr/sbin/visudo"

    // MARK: - Escaping helpers for building the privileged install command

    /// Quotes a path for safe use inside single-quoted shell strings ('…'),
    /// handling embedded single quotes.
    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes a plain string for embedding in an AppleScript string literal
    /// ("…"): backslashes first, then double quotes.
    static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
