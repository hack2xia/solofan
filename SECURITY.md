# Security Policy

## Supported Versions

Security fixes are applied to the latest SoloFan release line only.

| Version | Supported |
| ------- | --------- |
| 1.6.x   | Yes       |
| < 1.6   | No        |

Please upgrade to the latest release from [GitHub Releases](https://github.com/hack2xia/solofan/releases) or [Gumroad](https://lounnas.gumroad.com/l/ffan).

## Reporting a Vulnerability

If you find a security issue in SoloFan (including the privileged SMC helper, install scripts, or release artifacts), please report it privately so we can fix it before public disclosure.

**Preferred:** use GitHub’s private vulnerability reporting on this repository:

1. Open the repo on GitHub → **Security** → **Advisories** (or **Report a vulnerability**)
2. Or go to: https://github.com/hack2xia/solofan/security/advisories/new

**Alternatively**, email: **mohamadlounnas@gmail.com** with:

- A clear description of the issue
- Steps to reproduce
- Affected version / commit / platform (macOS version, Apple Silicon or Intel)
- Any proof-of-concept (non-destructive preferred)

Please **do not** open a public GitHub issue for security vulnerabilities.

## What to Expect

- We aim to acknowledge reports within **7 days**
- We will assess severity and work on a fix for the supported release line
- We may ask for more details; please keep the discussion private until a fix is released
- Once fixed, we will credit reporters if you want (optional)

## Privileged Helper

Fan control means writing SMC keys, which requires root. SoloFan does not ship a
setuid binary and does not install a launchd daemon. On first launch the app (or
`scripts/install.sh`) installs:

- `/usr/local/bin/smc-helper` — `root:wheel`, mode `0755`
- `/etc/sudoers.d/smc-fan-helper` — mode `0440`, containing
  `%admin ALL=(root) NOPASSWD: /usr/local/bin/smc-helper`

**Trust assumption:** this grants any process running as an admin user
passwordless root execution of that one binary path. An admin user can already
become root with their own password, so this removes a prompt rather than
granting a new class of access — but it does mean a process already running as
your admin user can drive the fans without further authentication.

The blast radius is bounded by the helper itself: its command surface is only
fan operations (`info`, `set <fan> <rpm>`, `auto <fan>`), it range-checks the fan
index against the number of fans the machine reports, and it clamps every target
to that fan's own `F{n}Mx` hardware ceiling. It cannot be used to write arbitrary
SMC keys.

To revoke, remove the helper and the drop-in:

```bash
sudo rm /usr/local/bin/smc-helper /etc/sudoers.d/smc-fan-helper
```

Deleting only the drop-in makes the app fall back to an admin password prompt per
write; deleting the helper disables fan control entirely.

## Scope Notes

SoloFan requires elevated privileges to talk to the SMC for fan control. Reports related to privilege escalation, helper tool abuse, install-script tampering, or notarization / distribution integrity are especially welcome.

For general bugs that are not security-sensitive, use [GitHub Issues](https://github.com/hack2xia/solofan/issues).
