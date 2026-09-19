# Third-Party Notices

SoloFan's own source is MIT-licensed — see [`LICENSE`](LICENSE). It ships one
third-party component under different terms.

## `smc-helper` — GPL

| | |
|---|---|
| **Sources** | `tools/smc-helper/smc.c`, `tools/smc-helper/smc.h` |
| **Origin** | Based on smcFanControl by devnull & Hendrik Holtmann, as recorded in the file headers |
| **License** | GPL — the file headers say "GPL License" without naming a version |
| **Built binary** | `tools/smc-helper/smc-helper`, copied to `fan/Resources/smc-helper` and into the app bundle |

The helper is compiled into a standalone executable. The app invokes it as a
subprocess via `sudo -n /usr/local/bin/smc-helper …`; it is not linked into the
Swift application binary. Its complete source lives in `tools/smc-helper/`
(`smc.c`, `smc.h`, `Makefile`) and here in this repository.

## What this means when redistributing

The signed app, the ZIP, and the DMG all contain `smc-helper`, so distributing
them also distributes the GPL component. That component's obligations apply to
it — source availability, the license text, and passing the same freedoms on to
recipients.

Two things are **not** currently in this repository and should be resolved before
shipping binaries:

1. **The GPL text itself.** No copy of the GPL is vendored. Add the version that
   matches the upstream project.
2. **The upstream version.** The headers do not state whether this is GPL-2.0 or
   GPL-3.0, which determines which text to include.

Nothing here is legal advice; it records what the sources currently say.
