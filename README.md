# SoloFan - Fan Control for macOS

A lightweight menu bar app for monitoring CPU/GPU temperatures and controlling fan speeds on macOS.

<!-- banner -->
![SoloFan banner](https://raw.githubusercontent.com/hack2xia/solofan/main/docs/assets/banner.png)

## Download

[**Download Latest Version (v1.6.6)**](https://github.com/hack2xia/solofan/releases/latest)

**Quick Start:**
1. Download the DMG from the link above
2. Drag **SoloFan.app** to `/Applications/`
3. Launch the app and click "Install Helper" when prompted
4. Enter your password once - that's it!

## Features

- 🌡️ **Temperature Monitoring**: Real-time CPU and GPU temperature readings
- 💨 **Fan Speed Control**: Manual fan speed adjustment or automatic temperature-based control
- 📊 **Visual Feedback**: Color-coded temperature indicators and speed gauges
- 🚀 **Launch at Login**: Automatic startup support using modern ServiceManagement API
- 🎨 **Modern UI**: Liquid glass design with SwiftUI

## Requirements

- **macOS 13 Ventura or later** — matches the Xcode project deployment target (`MACOSX_DEPLOYMENT_TARGET`). On macOS 26 the UI uses native Liquid Glass; older versions get an equivalent material-based styling.
- **Apple Silicon or Intel** (universal build when distributed from CI)

## Important Notes

### SMC Access

This app accesses the System Management Controller (SMC) to read temperatures and control fans. Due to macOS security restrictions:

1. **Temperature Reading**: Works on most Macs without special privileges
2. **Fan Control**: Requires root/admin privileges on modern macOS versions

### Helper Tool Installation

On first launch, the app will prompt you to install a helper tool. This is a **one-time setup**:

- Click "Install Helper" in the app
- Enter your admin password once
- The helper tool enables fan control without repeated password prompts

**Alternative:** Automated installation via Terminal
```bash
curl -fsSL https://raw.githubusercontent.com/hack2xia/solofan/main/scripts/install.sh | bash
```

This script downloads the latest version, installs SoloFan, sets up the helper tool, and launches the app automatically.

### Demo Mode

If you want to test the UI without installing the helper tool, enable Demo Mode from the app menu to see simulated data.

## Architecture

### Files

- **App/SoloFanApp.swift**: App entry point and AppDelegate (menu bar lifecycle, quit restore)
- **Core/SystemMonitor.swift**: SMC communication — temperature, fan speed, hardware limits
- **Core/FanController.swift**: Fan control logic (manual + auto curve) and helper invocation
- **Core/FanRPMBounds.swift**: RPM and temperature limits shared by the UI and the write path
- **Core/PermissionsManager.swift**: Installs the privileged helper and the sudoers rule
- **Core/StatusBarManager.swift**: Menu bar icon and popover management
- **Core/SettingsWindowController.swift**: AppKit window hosting the SwiftUI settings view
- **Core/LaunchAtLoginManager.swift**: Login item registration (SMAppService for macOS 13+)
- **Core/BatteryMonitor.swift**: Battery and power telemetry
- **Core/MenuBarIconPreferences.swift**: Menu bar visibility and icon preferences
- **FanControlViewModel.swift**: Main view model with Combine bindings
- **UI/Views/**: `PopoverView`, `SettingsView`, `TemperatureView`, `FanSpeedView`, `ContentView`
- **UI/Dashboard/**: Widget dashboard — models, layout engine, store, grid
- **UI/Modifiers/LiquidGlassModifier.swift**: macOS 26 Liquid Glass styling with a material fallback
- **Resources/smc-helper**: The privileged helper binary (built from `tools/smc-helper`)

### SMC Keys Used

**Temperature sensors** — probed in order, first readable value wins:

- Intel: `TC0P`, `TCXC`, `TC0E`, `TC0F`, `TC0D`, `TC1C`–`TC4C` (CPU);
  `TGDD`, `TG0P`, `TG0D`, `TG0E`, `TG0F` (GPU)
- Apple Silicon: `Tp01`, `Tp05`, `Tp09`, `Tp0D`, `Tp0H`, `Tp0L`, `Tp0P`, `Tp0T`,
  `Tp0X`, `Tp0b`…`Tp0z`, `Tp19`…`Tp1v`, `Te05`, `Te0L`, `Te0P`, `Te0S` (CPU/die);
  `Tg05`, `Tg0D`, `Tg0L`, `Tg0T`, `Tg0V`, `Tg0f`, `Tg0j`, `Tg1f`, `Tg1j` (GPU)

**Fan control:**

- `F%dAc` — actual fan speed
- `F%dMn`, `F%dMx` — hardware min/max; every write is clamped to `F%dMx`
- `F%dTg` — target fan speed (written for manual control)
- `F%dMd` / `F%dmd` — fan mode, 0 = auto, 1 = manual. Casing varies by silicon
  (lowercase on M5)
- `Ftst` — force-test key, written to 1 to suppress `thermalmonitord` while
  taking manual control and back to 0 to release it. Absent on M5.

## Control Modes

### Manual Mode
- Set a fixed fan speed using the slider (unified, or per fan)
- Speed is maintained regardless of temperature

### Automatic Mode

The app keeps manual control of the fans and drives them along a curve — it does
**not** hand them back to the system:

- **At or below Threshold**: fans sit at the floor (`F%dMn`)
- **Above Threshold**: linear ramp toward **Auto max speed**, reaching it at 90 °C
- **Response** bends that curve: below 1.5 favours the floor, above 1.5 favours the ceiling
- **88 °C and above**: an emergency override ignores **Auto max speed** and drives
  every fan to its hardware maximum (`F%dMx`)

## Build Configuration

The project uses:
- Sandbox: **Disabled** (required for SMC access)
- Hardened Runtime: **Enabled**
- IOKit Framework: Linked
- ServiceManagement Framework: Linked

## Known Limitations

1. **Apple Silicon Macs**: SMC structure may differ; some temperature keys may not work
2. **Fan Control**: Writing to SMC requires elevated privileges
3. **Sandbox**: Must be disabled for SMC access; not suitable for App Store

## License

SoloFan's own source — the Swift app, the UI, and the build tooling — is **MIT**;
see [`LICENSE`](LICENSE).

It ships one component under different terms:

- **`smc-helper`** is built from `tools/smc-helper/smc.{c,h}`, which derives from
  smcFanControl by devnull & Hendrik Holtmann and is **GPL**-licensed, as stated
  in its file headers. It is compiled into a standalone executable that the app
  runs as a subprocess (`sudo -n /usr/local/bin/smc-helper …`); it is not linked
  into the Swift binary, and its sources live entirely in `tools/smc-helper/`.

Built apps and DMGs therefore contain a GPL component, so redistributing them
carries that component's obligations (source availability and license text among
them). See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for the details.
The MIT license covers the rest and does permit commercial distribution.

## Troubleshooting

### No Temperature Data
- Ensure the app has SMC access (not sandboxed)
- Try running with sudo for full access
- Enable Demo Mode to test the UI

### Fan Control Not Working
- Fan control requires root privileges on modern macOS
- Run with `sudo` or create a privileged helper tool

### App Not Appearing in Menu Bar
- Check if the app is running in Activity Monitor
- Look for the fan icon in the menu bar
