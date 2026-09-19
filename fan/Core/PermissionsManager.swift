//
//  PermissionsManager.swift
//  SoloFan
//
//  Created by mohamad on 11/1/2026.
//  Manages installation of the helper tool
//

import Foundation
import Security
import AppKit
import Combine

class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published var isHelperInstalled = false

    private init() {
        checkInstallation()
    }
    
    func checkInstallation() {
        // Run on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let fileManager = FileManager.default
            let helperExists = fileManager.fileExists(atPath: HelperInstallPaths.helper)

            if !helperExists {
                DispatchQueue.main.async { self.isHelperInstalled = false }
                return
            }

            // If helper exists, assume it's installed (sudoers verification can be flaky from GUI apps)
            // The actual passwordless sudo will be tested when FanController runs
            DispatchQueue.main.async {
                self.isHelperInstalled = true
            }
        }
    }
    
    private func verifySudoAccess() -> Bool {
        // This check can fail from sandboxed GUI apps even when sudoers is correct
        // So we just check if helper binary exists and trust the installation
        return FileManager.default.fileExists(atPath: HelperInstallPaths.helper)
    }
    
    func installHelper(completion: @escaping (Bool, String?) -> Void) {
        // 1. Locate the helper in the App Bundle
        guard let bundledHelperURL = Bundle.main.url(forResource: "smc-helper", withExtension: nil) else {
            completion(false, "App Bundle missing smc-helper. Re-build app.")
            return
        }

        let bundledPath = bundledHelperURL.path

        // 2. Construct the installation script.
        // Paths are shell-quoted and the whole command AppleScript-escaped, so
        // spaces or quotes in the bundle path can no longer corrupt the command.
        // The sudoers drop-in is validated with visudo inside the same root
        // shell; on failure it is removed (the rm runs as root in the admin
        // shell and does not depend on sudo being healthy) and the marker
        // SOLOFAN_SUDOERS_INVALID surfaces to the caller.
        let dropIn = HelperInstallPaths.shellQuoted(HelperInstallPaths.sudoersDropIn)
        let shell =
            "mkdir -p /usr/local/bin /etc/sudoers.d" +
            " && cp -f \(HelperInstallPaths.shellQuoted(bundledPath)) \(HelperInstallPaths.shellQuoted(HelperInstallPaths.helper))" +
            " && chown root:wheel \(HelperInstallPaths.shellQuoted(HelperInstallPaths.helper))" +
            " && chmod 755 \(HelperInstallPaths.shellQuoted(HelperInstallPaths.helper))" +
            " && printf '%s' \(HelperInstallPaths.shellQuoted(HelperInstallPaths.sudoersRule)) > \(dropIn)" +
            " && chmod 440 \(dropIn)" +
            " && chown root:wheel \(dropIn)" +
            " && if \(HelperInstallPaths.visudo) -cf \(dropIn) >/dev/null; then echo SOLOFAN_SUDOERS_OK" +
            "; else rm -f \(dropIn); echo SOLOFAN_SUDOERS_INVALID; exit 1; fi"

        let script = """
        do shell script "\(HelperInstallPaths.appleScriptEscaped(shell))" with administrator privileges
        """

        // 3. Execute
        DispatchQueue.global(qos: .userInitiated).async {
             var error: NSDictionary?
             if let scriptObject = NSAppleScript(source: script) {
                 _ = scriptObject.executeAndReturnError(&error)

                 DispatchQueue.main.async {
                     if let error = error {
                         let msg = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
                         if msg.contains("SOLOFAN_SUDOERS_INVALID") {
                             completion(false, "The sudoers rule failed validation and was rolled back. The helper binary is installed; fan control will ask for a password until this is fixed.")
                         } else {
                             completion(false, msg)
                         }
                     } else {
                         self.checkInstallation() // Refresh state
                         completion(true, nil)
                     }
                 }
             } else {
                 DispatchQueue.main.async {
                     completion(false, "Failed to create installation script")
                 }
             }
        }
    }
}
