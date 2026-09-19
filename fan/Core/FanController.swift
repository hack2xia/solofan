//
//  FanController.swift
//  SoloFan
//
//  Created by mohamad on 11/1/2026.
//  SMC fan control with per-fan targets and hardware-derived RPM limits.
//

import Foundation
import Combine
import IOKit

enum ControlMode: String, CaseIterable {
    case manual
    case automatic
}

/// Terminal state of one queued apply. `.superseded` means a newer operation
/// (restore, generation bump) took over mid-flight — it updates neither the
/// status message nor `lastAppliedSpeed`, but MUST still clear in-flight
/// backpressure flags.
enum ApplyOutcome {
    case success
    case failure
    case superseded
}

class FanController: ObservableObject {
    @Published var mode: ControlMode = .manual
    /// Unified manual target (single slider / legacy settings).
    @Published var manualSpeed: Int = 2000
    /// When `perFanManualControl` is true, each index maps to `F%dTg` for fan `d`.
    @Published var manualSpeeds: [Int] = []
    @Published var perFanManualControl: Bool = false

    @Published var autoThreshold: Double = 60.0
    @Published var autoMaxSpeed: Int = 4500
    @Published var autoAggressiveness: Double = 1.5  // 0.0 = always min, 1.5 = temp-based, 3.0 = always max
    @Published var isControlEnabled = false
    @Published var lastWriteSuccess = false
    @Published var statusMessage: String = ""
    /// Largest target RPM last applied (used for auto-mode hysteresis).
    @Published var lastAppliedSpeed: Int = 0

    private weak var systemMonitor: SystemMonitor?
    /// Where the user's fan preferences live. Injectable so tests can run
    /// against a scratch suite instead of overwriting the real app's settings.
    private let defaults: UserDefaults
    private var autoControlTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Serializes privileged-helper invocations off the main thread so a slider
    /// drag (or the auto loop) never blocks the UI on sudo + waitUntilExit.
    private let applyQueue = DispatchQueue(label: "com.solofan.fan-apply", qos: .userInitiated)

    private var smcHelperPath: String {
        "/usr/local/bin/smc-helper"
    }

    // MARK: - Write coordination state (main-thread only)
    //
    // None of these need a lock. `writeGeneration` is read from `applyQueue`
    // blocks, which is safe for a specific reason worth writing down so nobody
    // "fixes" it later:
    //
    // A restore first bumps the generation on the main thread, THEN enqueues
    // the restore block on the serial `applyQueue`. By FIFO, any queued block
    // that could still read a stale generation necessarily starts (and
    // finishes) BEFORE the restore block runs — so the restore remains the
    // final SMC operation either way. A stale read costs at most one redundant
    // write that the restore immediately overwrites; it can never violate
    // ordering. The generation check is therefore a drain accelerator (stale
    // blocks skip in microseconds instead of taking ~10s each), not the
    // correctness anchor — the serial queue's FIFO order is.
    private var writeGeneration = 0
    /// Set on the quit/sleep paths. A queued AppleScript fallback checks this
    /// on the main thread before prompting, so an admin password dialog can
    /// never pop while the main thread is blocked waiting for the restore (or
    /// the machine is suspending). Cleared only by `reapplySettings` on wake.
    private var suppressAdminFallback = false
    /// One pending admin-prompt at a time (checks/prompt all run on main).
    private var appleScriptFallbackInFlight = false
    /// Auto-mode backpressure: a failed apply can take ~10s (unlock retry
    /// loop); without this, a stable target that keeps failing would enqueue
    /// a new attempt every 2s tick and pile up on the serial queue.
    private var autoApplyInFlight = false

    init(systemMonitor: SystemMonitor, defaults: UserDefaults = .standard) {
        self.systemMonitor = systemMonitor
        self.defaults = defaults
        loadSettings()

        systemMonitor.$fanMaxSpeeds
            .combineLatest(systemMonitor.$fanMinSpeeds, systemMonitor.$numberOfFans)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, fanCount in
                guard let self = self, fanCount > 0 else { return }
                self.onHardwareLimitsUpdated()
            }
            .store(in: &cancellables)

        systemMonitor.$numberOfFans
            .receive(on: DispatchQueue.main)
            .filter { $0 > 0 }
            .first()
            .sink { [weak self] _ in
                print("FanController: Fans detected, applying initial settings")
                self?.applyInitialSettings()
            }
            .store(in: &cancellables)
    }

    deinit {
        stopAutoControl()
        // Restoring system control here was dead code: `restoreAutomaticControl`
        // hops onto `applyQueue` and captures `self` weakly, so by the time the
        // block runs the object is gone and its guard returns immediately.
        // Restoring now happens on the quit path
        // (`restoreAutomaticControlSync`) and once at launch
        // (`releaseFansToSystem`).
    }

    // MARK: - Hardware-derived clamps

    private var unifiedMinClamp: Int {
        systemMonitor?.fanMinSpeeds.min() ?? FanRPMBounds.fallbackMinWhenSMCUnreadable
    }

    private var unifiedMaxClamp: Int {
        systemMonitor?.fanMaxSpeeds.max() ?? FanRPMBounds.fallbackMaxWhenSMCUnreadable
    }

    private func minRPM(for index: Int) -> Int {
        guard let monitor = systemMonitor,
              index >= 0,
              index < monitor.fanMinSpeeds.count else {
            return FanRPMBounds.fallbackMinWhenSMCUnreadable
        }
        return monitor.fanMinSpeeds[index]
    }

    private func maxRPM(for index: Int) -> Int {
        guard let monitor = systemMonitor,
              index >= 0,
              index < monitor.fanMaxSpeeds.count else {
            return FanRPMBounds.fallbackMaxWhenSMCUnreadable
        }
        return monitor.fanMaxSpeeds[index]
    }

    private func clampToFan(_ speed: Int, index: Int) -> Int {
        max(minRPM(for: index), min(maxRPM(for: index), speed))
    }

    private func clampUnified(_ speed: Int) -> Int {
        max(unifiedMinClamp, min(unifiedMaxClamp, speed))
    }

    private func onHardwareLimitsUpdated() {
        guard let monitor = systemMonitor, monitor.numberOfFans > 0 else { return }
        ensureManualSpeedsSize()
        // Do NOT clamp the stored preferences (manualSpeed / autoMaxSpeed) to the live
        // hardware max here. F{n}Mx reads intermittently on Apple Silicon — it flips to
        // the unreadable fallback — and this fires on every such flip, so clamping would
        // repeatedly shrink and re-save the user's ceiling (the "max speed forgets itself"
        // bug). Targets are clamped to the real limit at apply time instead, so a low
        // reading never spins the fan past hardware while the preference is preserved.
        if mode == .manual && isControlEnabled {
            applyManualTargets()
        } else if mode == .automatic && isControlEnabled {
            lastAppliedSpeed = 0
            updateAutoControl()
        }
    }

    private func ensureManualSpeedsSize() {
        guard let monitor = systemMonitor, monitor.numberOfFans > 0 else { return }
        let n = monitor.numberOfFans
        if manualSpeeds.count < n {
            var copy = manualSpeeds
            let template = copy.last ?? manualSpeed
            while copy.count < n {
                let idx = copy.count
                copy.append(clampToFan(template, index: idx))
            }
            manualSpeeds = copy
        } else if manualSpeeds.count > n {
            manualSpeeds = Array(manualSpeeds.prefix(n))
        }
    }

    private func syncManualSpeedsFromUnified() {
        guard let monitor = systemMonitor, monitor.numberOfFans > 0 else { return }
        manualSpeeds = (0..<monitor.numberOfFans).map { clampToFan(manualSpeed, index: $0) }
    }

    // MARK: - Lifecycle

    private func applyInitialSettings() {
        print("FanController: Applying initial settings - mode: \(mode)")

        // A previous run may have died without handing the fans back (crash,
        // `kill -9`, power loss), leaving F{n}Md=1 and — worse — Ftst=1, which
        // keeps thermalmonitord suppressed until something writes Ftst=0. Only
        // `smc-helper auto` clears it (see unlockFanManual/setFanAuto in smc.c),
        // so always release the fans once at launch before applying settings.
        // Enqueued on the same serial queue as the apply below, so it runs first.
        releaseFansToSystem()

        switch mode {
        case .manual:
            enableManualMode()
            ensureManualSpeedsSize()
            if !perFanManualControl {
                syncManualSpeedsFromUnified()
            }
            applyManualTargets()
        case .automatic:
            startAutoControl()
        }
    }

    func reapplySettings() {
        // Wake path: the quit/sleep restore that set this flag has had its
        // chance; admin prompts are allowed again.
        suppressAdminFallback = false
        print("FanController: Reapplying settings after wake - mode: \(mode)")
        guard let monitor = systemMonitor, monitor.numberOfFans > 0 else {
            print("FanController: No fans detected yet, retrying in 2 seconds...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.reapplySettings()
            }
            return
        }

        switch mode {
        case .manual:
            enableManualMode()
            ensureManualSpeedsSize()
            if !perFanManualControl {
                syncManualSpeedsFromUnified()
            }
            applyManualTargets()
            print("FanController: Manual mode reapplied")
        case .automatic:
            enableManualMode()
            startAutoControl()
            lastAppliedSpeed = 0
            updateAutoControl()
            print("FanController: Auto mode reapplied")
        }
    }

    /// Toggle independent sliders for each fan (manual mode only).
    func setPerFanManualControl(_ enabled: Bool) {
        perFanManualControl = enabled
        if enabled {
            syncManualSpeedsFromUnified()
        } else {
            if !manualSpeeds.isEmpty {
                let avg = Int(round(Double(manualSpeeds.reduce(0, +)) / Double(manualSpeeds.count)))
                manualSpeed = clampUnified(avg)
            }
            syncManualSpeedsFromUnified()
        }
        saveSettings()
        if mode == .manual && isControlEnabled {
            applyManualTargets()
        }
    }

    func setManualSpeed(_ speed: Int) {
        guard mode == .manual else { return }
        manualSpeed = clampUnified(speed)
        if !perFanManualControl {
            syncManualSpeedsFromUnified()
        }
        if isControlEnabled {
            applyManualTargets()
        }
        saveSettings()
    }

    func setManualSpeed(fanIndex: Int, speed: Int) {
        guard mode == .manual, perFanManualControl else { return }
        ensureManualSpeedsSize()
        guard fanIndex >= 0, fanIndex < manualSpeeds.count else { return }
        var next = manualSpeeds
        next[fanIndex] = clampToFan(speed, index: fanIndex)
        manualSpeeds = next
        saveSettings()
        if isControlEnabled {
            applyManualTargets()
        }
    }

    func setMode(_ newMode: ControlMode) {
        mode = newMode

        if newMode == .automatic {
            restoreAutomaticControl()
            startAutoControl()
        } else {
            stopAutoControl()
            enableManualMode()
            ensureManualSpeedsSize()
            if !perFanManualControl {
                syncManualSpeedsFromUnified()
            }
            applyManualTargets()
        }

        saveSettings()
    }

    private func enableManualMode() {
        guard systemMonitor != nil else {
            statusMessage = "No system monitor available"
            return
        }
        isControlEnabled = true
        statusMessage = "Manual control enabled"
        print("Fan Control: Manual control enabled")
    }

    func restoreAutomaticControl() {
        guard let monitor = systemMonitor else { return }
        let n = monitor.numberOfFans
        guard n > 0 else { return }

        // Queued manual writes are about to be superseded by this restore;
        // bump the generation so they abandon themselves instead of running
        // pointlessly ahead of it. The restore block enqueued below is ordered
        // after everything already queued (serial FIFO), so it stays final.
        writeGeneration += 1

        applyQueue.async { [weak self] in
            guard let self = self else { return }
            var allSuccess = true
            for i in 0..<n {
                if !self.runSmcHelper(args: ["auto", "\(i)"]) {
                    allSuccess = false
                }
            }
            DispatchQueue.main.async {
                if allSuccess {
                    self.isControlEnabled = false
                    self.statusMessage = "Automatic mode restored"
                    print("Fan Control: Automatic mode restored")
                } else {
                    self.statusMessage = "Failed to restore auto mode"
                    print("Fan Control: Failed to restore auto mode")
                }
            }
        }
    }

    /// Quit-path variant of `restoreAutomaticControl`: blocks (bounded by
    /// `timeout`) until every fan is back under system control, so `terminate`
    /// cannot race the restore the way fire-and-forget + a 0.5s wait did.
    ///
    /// Ordering guarantees, in order of importance:
    /// 1. Serial-queue FIFO: the restore block is enqueued on `applyQueue`
    ///    after everything already queued, so it always runs LAST — a queued
    ///    slider write can no longer land after the restore and re-pin the
    ///    fan in manual mode (the bug this function exists to prevent).
    /// 2. Generation bump first: queued-but-unstarted writes abandon
    ///    themselves, so the drain before the restore is microseconds instead
    ///    of up to ~10s per in-flight helper call.
    /// 3. Bounded wait: the semaphore caps main-thread blocking; on timeout
    ///    the barrier stays queued (quit: dies with the process, and launch
    ///    `releaseFansToSystem` clears the rest; sleep: completes after wake).
    ///
    /// The AppleScript fallback is disabled — prompting for a password on the way
    /// out is useless, and anything left behind is cleared by
    /// `releaseFansToSystem()` on the next launch.
    @discardableResult
    func restoreAutomaticControlSync(timeout: TimeInterval = 2.0) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        stopAutoControl()

        guard let monitor = systemMonitor, monitor.numberOfFans > 0 else { return false }
        let n = monitor.numberOfFans

        suppressAdminFallback = true
        writeGeneration += 1

        var allSuccess = true
        let semaphore = DispatchSemaphore(value: 0)
        applyQueue.async { [weak self] in
            guard let self = self else {
                semaphore.signal()
                return
            }
            for i in 0..<n {
                if !self.runSmcHelper(args: ["auto", "\(i)"], allowAppleScriptFallback: false) {
                    allSuccess = false
                }
            }
            semaphore.signal()
        }

        // signal() → wait() returning gives the happens-before edge, so
        // reading `allSuccess` here is safe. The main run loop does NOT spin
        // while we wait — which is exactly what we want: no timer fire, no
        // queued main-thread work (including admin prompts) can run.
        let waitResult = semaphore.wait(timeout: .now() + timeout)
        let success = (waitResult == .success && allSuccess)

        if success {
            isControlEnabled = false
            statusMessage = "Automatic mode restored"
            print("Fan Control: Automatic mode restored (synchronous)")
        } else {
            print("Fan Control: restore incomplete after \(timeout)s (waitResult=\(waitResult == .success ? "success" : "timedOut"))")
        }
        return success
    }

    /// Hands every fan back to the system (`F{n}Md=0`, and `Ftst=0` via
    /// `smc-helper auto`) without touching published state or user settings.
    /// Used at launch to clear whatever a previous run left behind.
    private func releaseFansToSystem() {
        guard let monitor = systemMonitor, monitor.numberOfFans > 0 else { return }
        let n = monitor.numberOfFans
        applyQueue.async { [weak self] in
            guard let self = self else { return }
            for i in 0..<n {
                _ = self.runSmcHelper(args: ["auto", "\(i)"])
            }
        }
    }

    private func applyManualTargets() {
        guard let monitor = systemMonitor else {
            statusMessage = "No system monitor"
            lastWriteSuccess = false
            return
        }
        guard monitor.numberOfFans > 0 else {
            statusMessage = "No fans detected"
            lastWriteSuccess = false
            return
        }

        ensureManualSpeedsSize()
        var targets: [Int] = []
        for i in 0..<monitor.numberOfFans {
            let raw: Int
            if perFanManualControl, i < manualSpeeds.count {
                raw = manualSpeeds[i]
            } else {
                raw = manualSpeed
            }
            targets.append(clampToFan(raw, index: i))
        }
        applyFanTargets(targets)
    }

    /// Enqueues one fan-target write batch. Must be called on the main thread.
    /// `completion` (if given) fires exactly once, on the main thread, with
    /// the terminal outcome — including `.failure` from the early guards —
    /// so callers holding backpressure flags never leak them.
    private func applyFanTargets(_ targets: [Int], completion: ((ApplyOutcome) -> Void)? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let monitor = systemMonitor else {
            statusMessage = "No system monitor"
            lastWriteSuccess = false
            completion?(.failure)
            return
        }
        guard monitor.numberOfFans > 0, targets.count == monitor.numberOfFans else {
            statusMessage = "Fan target mismatch"
            lastWriteSuccess = false
            completion?(.failure)
            return
        }

        // Spawning the privileged helper blocks: sudo + waitUntilExit, and the
        // helper itself sleeps while taking manual control. Running that on the
        // main thread freezes the UI mid slider-drag. Serialize applies onto a
        // background queue and only touch @Published state back on main.
        let generation = writeGeneration
        applyQueue.async { [weak self] in
            guard let self = self else { return }
            var allSuccess = true
            var superseded = false
            for (i, t) in targets.enumerated() {
                // Generation re-check per fan: a restore that bumped the
                // generation while this block was queued (or mid-loop) makes
                // the remaining writes pointless. See the state declaration
                // comment for why this needs no lock.
                if self.writeGeneration != generation {
                    superseded = true
                    break
                }
                let safe = max(FanRPMBounds.absoluteWriteMinRPM, min(FanRPMBounds.absoluteWriteMaxRPM, t))
                if !self.runSmcHelper(args: ["set", "\(i)", "\(safe)"]) {
                    allSuccess = false
                }
            }
            let outcome: ApplyOutcome = superseded ? .superseded : (allSuccess ? .success : .failure)
            DispatchQueue.main.async {
                switch outcome {
                case .success:
                    let parts = targets.enumerated().map { "F\($0.offset): \($0.element)" }.joined(separator: ", ")
                    self.statusMessage = "Fan targets RPM — \(parts)"
                    self.lastWriteSuccess = true
                    print("Fan Control: \(parts)")
                case .failure:
                    self.statusMessage = "Failed to set fan speed"
                    self.lastWriteSuccess = false
                case .superseded:
                    break // newer operation owns the published state now
                }
                completion?(outcome)
            }
        }
    }

    /// Runs the privileged helper. `allowAppleScriptFallback` is false on the
    /// quit path: an admin prompt there is pointless (the process is exiting)
    /// and the next launch clears whatever is left behind anyway.
    private func runSmcHelper(args: [String], allowAppleScriptFallback: Bool = true) -> Bool {
        let helperPath = smcHelperPath

        // Runs on a background queue — do not touch @Published here. Callers map
        // the false return to a status message back on the main thread.
        if !FileManager.default.fileExists(atPath: helperPath) {
            print("Error: \(helperPath) not found")
            return false
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", helperPath] + args
        task.environment = ["LANG": "C"]
        let stderrPipe = Pipe()
        task.standardError = stderrPipe

        do {
            try task.run()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                return true
            }
            // Two failures exit non-zero: sudo refusing to run us (a privilege
            // problem the password prompt can fix) and the helper running AS ROOT
            // then failing — e.g. thermalmonitord transiently holding the fan in
            // SYSTEM mode right after wake, where unlockFanManual loses the reclaim
            // race. Re-running the latter under admin privileges hits the same SMC
            // failure and only pops a spurious password dialog. Only sudo's own
            // refusal warrants the AppleScript fallback, and sudo prefixes those
            // messages with "sudo:".
            let stderr = String(data: errData, encoding: .utf8) ?? ""
            if !stderr.contains("sudo:") {
                print("Fan Control: helper ran as root and failed (exit \(task.terminationStatus)): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
                return false
            }
        } catch {
            print("Fan Control: sudo -n execution error: \(error)")
        }

        guard allowAppleScriptFallback else {
            print("Fan Control: sudo -n unauthorized; AppleScript fallback disabled for this call.")
            return false
        }

        print("Fan Control: sudo -n unauthorized. Falling back to AppleScript (async).")

        // This call reports failure and returns immediately; the actual prompt
        // is dispatched asynchronously to the main thread. It MUST NOT
        // `DispatchQueue.main.sync` back: the quit/sleep restore blocks the
        // main thread on a semaphore waiting for this queue, so a synchronous
        // hop would deadlock the restore. The auto loop retries on the next
        // tick, and the dispatched block updates the published state if the
        // prompt eventually succeeds.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            defer { self.appleScriptFallbackInFlight = false }
            // Re-check on main: suppress during quit/sleep restore, and only
            // one pending prompt at a time (the 2s auto tick would otherwise
            // stack password dialogs on every failed sudo -n).
            if self.suppressAdminFallback || self.appleScriptFallbackInFlight {
                print("Fan Control: admin prompt suppressed or already pending.")
                return
            }
            self.appleScriptFallbackInFlight = true

            let argsString = args.joined(separator: " ")
            let fullCommand = "'\(helperPath)' \(argsString)"
            let scriptSource = "do shell script \"\(fullCommand)\" with administrator privileges"

            var error: NSDictionary?
            guard let scriptObject = NSAppleScript(source: scriptSource) else {
                self.statusMessage = "Failed to set fan speed"
                self.lastWriteSuccess = false
                return
            }
            _ = scriptObject.executeAndReturnError(&error)
            if let error = error {
                let errorMsg = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
                print("Fan Control: AppleScript failed: \(errorMsg)")
                self.statusMessage = "Failed to set fan speed"
                self.lastWriteSuccess = false
            } else {
                // The synchronous return already reported failure; keep the
                // published state truthful about what actually happened.
                self.lastWriteSuccess = true
            }
        }
        return false
    }

    func startAutoControl() {
        stopAutoControl()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateAutoControl()
            self.autoControlTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.updateAutoControl()
            }
            RunLoop.current.add(self.autoControlTimer!, forMode: .common)
        }
    }

    func stopAutoControl() {
        autoControlTimer?.invalidate()
        autoControlTimer = nil
    }

    private func updateAutoControl() {
        guard mode == .automatic, let monitor = systemMonitor else { return }

        let currentTemp = max(
            monitor.cpuTemperature ?? 0,
            monitor.gpuTemperature ?? 0
        )

        guard currentTemp > 0, monitor.numberOfFans > 0 else { return }

        if !isControlEnabled {
            enableManualMode()
        }

        let autoCeiling = min(autoMaxSpeed, unifiedMaxClamp)
        let autoFloor = unifiedMinClamp

        // Curve math lives in FanCurve (pure, unit-tested); this function only
        // wires telemetry in and gates the apply.
        let unifiedTarget = FanCurve.unifiedTarget(
            temperature: currentTemp,
            threshold: autoThreshold,
            aggressiveness: autoAggressiveness,
            floorRPM: autoFloor,
            ceilingRPM: autoCeiling
        )

        let mins = (0..<monitor.numberOfFans).map { minRPM(for: $0) }
        let maxs = (0..<monitor.numberOfFans).map { maxRPM(for: $0) }
        let targets = FanCurve.targets(
            unified: unifiedTarget,
            temperature: currentTemp,
            fanMins: mins,
            fanMaxs: maxs,
            ceilingRPM: autoCeiling
        )

        let representative = targets.max() ?? unifiedTarget
        let emergency = currentTemp >= FanRPMBounds.emergencyTemperature

        // Backpressure: one auto apply in flight at a time (a failing helper
        // call can take ~10s; the 2s tick would otherwise pile up attempts).
        // Emergency targets bypass the 50-RPM dedup entirely — a first failed
        // emergency write must never silence the emergency. lastAppliedSpeed
        // is updated ONLY on .success, so a failed apply with a stable target
        // naturally retries on the next tick instead of being deduped away.
        if !autoApplyInFlight,
           FanCurve.shouldApply(newRepresentative: representative,
                                lastApplied: lastAppliedSpeed,
                                isEmergency: emergency) {
            autoApplyInFlight = true
            applyFanTargets(targets) { [weak self] outcome in
                guard let self = self else { return }
                self.autoApplyInFlight = false
                if case .success = outcome {
                    self.lastAppliedSpeed = representative
                }
            }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let parts = targets.enumerated().map { "F\($0.offset): \($0.element)" }.joined(separator: ", ")
            if emergency {
                self.statusMessage = "Emergency — \(parts) (≥\(Int(FanRPMBounds.emergencyTemperature))°C)"
            } else {
                self.statusMessage = "Auto — \(parts) (response \(String(format: "%.1f", self.autoAggressiveness)))"
            }
        }
        }
    }

    private func loadSettings() {
        if let savedMode = defaults.string(forKey: "fanControlMode") {
            mode = ControlMode(rawValue: savedMode) ?? .manual
        }

        perFanManualControl = defaults.bool(forKey: "perFanManualControl")

        let savedManualSpeed = defaults.integer(forKey: "manualFanSpeed")
        if savedManualSpeed >= FanRPMBounds.absoluteWriteMinRPM && savedManualSpeed <= FanRPMBounds.absoluteWriteMaxRPM {
            manualSpeed = savedManualSpeed
        }

        if let savedPerFan = defaults.array(forKey: "manualFanSpeedsPerFan") as? [Int], !savedPerFan.isEmpty {
            manualSpeeds = savedPerFan
        }

        let savedThreshold = defaults.double(forKey: "autoThreshold")
        if savedThreshold >= 40 && savedThreshold <= 90 {
            autoThreshold = savedThreshold
        }

        let savedMaxSpeed = defaults.integer(forKey: "autoMaxSpeed")
        if savedMaxSpeed >= FanRPMBounds.absoluteWriteMinRPM && savedMaxSpeed <= FanRPMBounds.absoluteWriteMaxRPM {
            autoMaxSpeed = savedMaxSpeed
        }

        // `double(forKey:)` returns 0.0 for a missing key, and 0.0 passes the
        // range check below — which silently overwrote the declared default of
        // 1.5 on a fresh install ("always min speed"). Check for existence
        // first; an explicit 0.0 from the user remains a legal value.
        if defaults.object(forKey: "autoAggressiveness") != nil {
            let savedAggressiveness = defaults.double(forKey: "autoAggressiveness")
            if savedAggressiveness >= 0.0 && savedAggressiveness <= 3.0 {
                autoAggressiveness = savedAggressiveness
            }
        }
    }

    func resetToSystemControl() {
        print("Fan Control: Resetting to system default...")
        stopAutoControl()
        restoreAutomaticControl()
    }

    private func saveSettings() {
        defaults.set(mode.rawValue, forKey: "fanControlMode")
        defaults.set(perFanManualControl, forKey: "perFanManualControl")
        defaults.set(manualSpeed, forKey: "manualFanSpeed")
        defaults.set(manualSpeeds, forKey: "manualFanSpeedsPerFan")
        defaults.set(autoThreshold, forKey: "autoThreshold")
        defaults.set(autoMaxSpeed, forKey: "autoMaxSpeed")
        defaults.set(autoAggressiveness, forKey: "autoAggressiveness")
    }

    func setAutoThreshold(_ threshold: Double) {
        autoThreshold = max(40, min(90, threshold))
        saveSettings()
        if mode == .automatic {
            lastAppliedSpeed = 0
            updateAutoControl()
        }
    }

    func setAutoMaxSpeed(_ speed: Int) {
        autoMaxSpeed = clampUnified(speed)
        saveSettings()
        if mode == .automatic {
            lastAppliedSpeed = 0
            updateAutoControl()
        }
    }

    func setAutoAggressiveness(_ value: Double) {
        autoAggressiveness = max(0.0, min(3.0, value))
        saveSettings()
        if mode == .automatic {
            lastAppliedSpeed = 0
            updateAutoControl()
        }
    }
}
