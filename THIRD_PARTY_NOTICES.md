# Third-Party Notices

SoloFan's own source is MIT-licensed — see [`LICENSE`](LICENSE). It ships one
third-party component under different terms.

## `smc-helper` — GPL-2.0

| | |
|---|---|
| **Sources** | `tools/smc-helper/smc.c`, `tools/smc-helper/smc.h` |
| **Origin** | Based on smcFanControl by devnull & Hendrik Holtmann, as recorded in the file headers |
| **License** | GPL-2.0 — smcFanControl's upstream repository licenses the code under GPL-2.0; the headers here say "GPL License", meaning that same version |
| **License text** | [`LICENSES/GPL-2.0.txt`](LICENSES/GPL-2.0.txt), also bundled with the app at `SoloFan.app/Contents/Resources/GPL-2.0.txt` |
| **Built binary** | `tools/smc-helper/smc-helper`, copied to `fan/Resources/smc-helper` and into the app bundle |

The helper is compiled into a standalone executable. The app invokes it as a
subprocess via `sudo -n /usr/local/bin/smc-helper …`; it is not linked into the
Swift application binary. Its complete source lives in `tools/smc-helper/`
(`smc.c`, `smc.h`, `Makefile`) and here in this public repository, which
satisfies GPL-2.0 §3's source-availability requirement for binary distribution.

## What this means when redistributing

The signed app, the ZIP, and the DMG all contain `smc-helper`, so distributing
them also distributes the GPL-2.0 component. That component's obligations apply
to it — keep the license text (bundled at `Contents/Resources/GPL-2.0.txt`)
with the binaries, keep copyright notices intact, and pass the same freedoms
on to recipients. Note that GPL-2.0 explicitly permits charging for
redistribution; nothing in this repository restricts that freedom for the
helper.
