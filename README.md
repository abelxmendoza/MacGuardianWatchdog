# MacGuardian Suite

![MacGuardian Logo](MacGuardianSuiteUI/Resources/images/MacGuardianLogo.png)

**Comprehensive Security Suite for macOS**

A free, all-in-one security and maintenance platform for macOS combining antivirus, threat detection, behavioral analysis, automated remediation, and real-time monitoring.

[![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## What It Does

MacGuardian Suite is a native macOS app (SwiftUI) backed by shell and Python scripts. It gives you real security tools — not just a UI — in one place:

The app has nine tabs, one per job:

- **Dashboard** — security score from your last audit, open incidents, live system health, and MacGuardian's check on itself
- **Audit** — posture check (FileVault, SIP, Gatekeeper, firewall, automatic updates, Remote Login, startup items), file integrity against a baseline, SSH, user accounts, privacy permissions, and the **Self-Check**
- **Threats** — blue-team process and network analysis with live CPU, memory, disk and network figures
- **Incidents** — rule-based incidents and a timeline fed by the real-time monitor
- **Fix** — previewed, per-category remediation; quarantine instead of delete
- **Processes** — find and quit stubborn or runaway apps
- **Cleaner** — browser, system and Homebrew caches, Cursor caches, app icon cache
- **Reports** — generate and browse HTML security reports
- **Settings** — project folder and email reports

Antivirus and rootkit scans use ClamAV and rkhunter.

All data stays local. Nothing is sent to external servers except optional email reports you configure. See [SECURITY.md](SECURITY.md) for how to verify your download and what MacGuardian does on your Mac.

---

## Requirements

| Component | Minimum |
| --------- | ------- |
| macOS (SwiftUI app) | 14.0 (Sonoma) |
| macOS (shell scripts) | 12.0 (Monterey) |
| Xcode | Full Xcode (the app can't be built with Command Line Tools alone) |
| Homebrew | Optional, for ClamAV and rkhunter |

---

## Quick Start

### Option A — Native App (Recommended)

1. Download the zip (or `git clone https://github.com/abelxmendoza/MacGuardianWatchdog.git`) and unzip it.
2. In the unzipped folder, double-click **Install MacGuardian.command**, or in Terminal run:

```bash
bash install.sh
```

The installer:

- checks for macOS 14+ and Xcode (and tells you the exact command if the Xcode license still needs accepting)
- copies a downloaded zip to `~/Library/Application Support/MacGuardian/Suite`, so you can delete the download afterwards (a git clone stays where it is)
- prepares `~/.macguardian`
- offers to install ClamAV and rkhunter with Homebrew and download virus definitions
- builds the app, installs it to `/Applications`, and points it at its scripts automatically
- offers to schedule nightly file-integrity checks
- opens the app

Run it again any time to update. Options: `--yes` (accept every optional step), `--no-deps`, `--no-launch`.

If macOS says the `.command` file "cannot be opened", right-click it and choose **Open**, or use the Terminal command above.

### Option B — Command Line

```bash
git clone https://github.com/abelxmendoza/MacGuardianWatchdog.git
cd MacGuardianWatchdog
chmod +x mac_suite.sh MacGuardianSuite/*.sh
./mac_suite.sh
```

---

## Permissions

Some features require macOS permissions granted in **System Settings > Privacy & Security**:

| Permission | Required For |
| ---------- | ------------ |
| Full Disk Access | File integrity monitoring, baseline creation |
| Network Access | Threat intelligence feed updates |
| Accessibility | Advanced process monitoring (optional) |

---

## Core Modules

### mac_guardian.sh — Cleanup & Security

- Homebrew updates, macOS update checks
- ClamAV antivirus scan (fast mode by default)
- rkhunter rootkit detection
- Firewall, Gatekeeper, SIP, FileVault, Time Machine checks
- Checkpoint/resume support for interrupted runs
- HTML report generation

### mac_watchdog.sh — File Integrity Monitor

- SHA-256 baseline creation and incremental comparison
- Detects modifications, additions, and deletions
- Honeypot file monitoring
- Email alerts on changes

### mac_blueteam.sh — Threat Detection

- Process anomaly detection
- Network connection analysis and C2 detection
- File system anomaly scanning
- Behavioral pattern analysis and threat hunting
- Optional: osquery, nmap, yara integration

### mac_ai.sh / ai_engine.py / ml_engine.py — ML Analysis (command line, experimental)

Not shown in the app: its anomaly scores are still noisy.

- Behavioral anomaly detection
- File classification
- Predictive threat analysis
- Online learning (improves over time)

### mac_security_audit.sh — Security Audit

- FileVault, SIP, Gatekeeper, launch item checks
- SSL/TLS certificate monitoring
- Optional Lynis integration
- Scored output (pass/fail/warning per check)

### mac_remediation.sh — Auto-Fix

- Dry-run by default — preview before applying
- Quarantine instead of delete
- Rollback manifests with SHA-256 checksums
- File permission fixes, launch item cleanup, suspicious process reporting

---

## CLI Usage Reference

```bash
# Full interactive menu
./mac_suite.sh

# Individual modules
./MacGuardianSuite/mac_guardian.sh           # Security scan + cleanup
./MacGuardianSuite/mac_guardian.sh -y        # Non-interactive
./MacGuardianSuite/mac_guardian.sh -q        # Quiet mode
./MacGuardianSuite/mac_guardian.sh --report  # Generate HTML report

./MacGuardianSuite/mac_watchdog.sh
./MacGuardianSuite/mac_blueteam.sh --threat-hunt --nmap
./MacGuardianSuite/mac_security_audit.sh --lynis
./MacGuardianSuite/hardening_assessment.sh   # Hardening score (0-100)
./MacGuardianSuite/scheduled_reports.sh daily

# Set up launchd automation
./MacGuardianSuite/install_scheduler.sh
```

---

## Configuration

`~/.macguardian/config.conf` is created automatically on first run.

```bash
# Scanning
FAST_SCAN_DEFAULT=true
CLAMAV_MAX_FILESIZE=100M

# Notifications
ENABLE_NOTIFICATIONS=true
NOTIFICATION_COOLDOWN=300

# Parallel processing
ENABLE_PARALLEL=true

# Reporting
REPORT_EMAIL=""
REPORT_SCHEDULE="daily"
REPORT_FORMAT="html"

# Alerting
ALERT_EMAIL=""
ALERT_ENABLED=true
```

---

## Automated Scheduling

Scheduling is optional: `install.sh` asks, or run it yourself:

```bash
./MacGuardianSuite/install_scheduler.sh                # all three jobs
./MacGuardianSuite/install_scheduler.sh --jobs reports # only the daily report
./MacGuardianSuite/install_scheduler.sh --uninstall
```

Jobs run a private copy of the scripts from `~/Library/Application Support/MacGuardian` (macOS blocks background jobs from Desktop, Documents and Downloads). `install.sh` refreshes that copy on every update.

- **Daily at 2:00 AM** — Mac Watchdog (file integrity)
- **Sundays at 3:00 AM** — Mac Guardian (full security scan)
- **Daily at 9:00 AM** — Security report generation

---

## Recent Changes

### Simpler app
- 18 tabs and a script sidebar became 9 task-named tabs. Removed screens that didn't work: Real-Time Monitor (needed a server nothing started), Network Graph, the Threat Intel lookup, a duplicate Security tab and a history that never persisted.
- The Dashboard score now comes from your last Security Audit and survives restarts.
- Live screens (Incidents, Timeline, SSH, User Accounts, Privacy) read the monitor daemon's events directly; "Monitor running" means it really is.

### Install, trust and self-check
- `install.sh` / **Install MacGuardian.command**: one-step setup from a download or clone; `uninstall.sh` removes everything.
- **Self-check** (Dashboard, Audit → Self-Check, `self_check.sh`): verifies scripts against install-time fingerprints, file permissions, the app's code signature and background jobs.
- Background jobs run a private copy of the scripts, because macOS blocks them from Desktop/Documents/Downloads (scheduled reports had been failing with "Operation not permitted").
- No personal email address is built in any more; alerts go only to the address you configure.

### Fixes
- Fix tab: **Apply** now applies the fix (it previously ran a dry run and reported success), one category at a time.
- Suspicious-process checks no longer flag Malwarebytes or Apple system services, and no longer abort the scan on the first match.
- Security Audit: real JSON results, added firewall / automatic updates / Remote Login checks, removed a certificate check that always passed.
- Permission fixes now find world-writable files (the scan previously never matched anything).
- Event files are always valid JSON (about 10% were unreadable), the monitor reports each listening port once, and events older than 7 days are cleaned up.
- Counting bugs (`"0\n0"`) fixed across 14 scripts; Threats tab shows real system figures.

---

## Troubleshooting

### App won't launch

- Verify macOS 14.0+: `sw_vers`
- Verify Xcode: `xcode-select -p` should point inside `Xcode.app`
- Rebuild and reinstall: `bash install.sh` (build log: `~/.macguardian/logs/install-build.log`)

### Scripts not found

- Run `bash install.sh` again from the project folder; it re-links the app to its scripts
- Or set the project folder in **Settings → Repository**

### ClamAV not installed

```bash
brew install clamav
freshclam
```

### rkhunter not installed

```bash
brew install rkhunter
sudo rkhunter --update
```

### Debug mode

```bash
DEBUG=true ./MacGuardianSuite/mac_guardian.sh
```

### View error database

```bash
./MacGuardianSuite/view_errors.sh
```

### Verify all components

```bash
./MacGuardianSuite/verify_suite.sh
```

---

## Logs and Data

| Path | Contents |
| ---- | -------- |
| `~/.macguardian/logs/` | Script execution logs |
| `~/.macguardian/reports/` | Generated HTML security reports |
| `~/.macguardian/config.conf` | User configuration |
| `~/.macguardian/omega_guardian/` | Omega Guardian incidents and alert rules |
| `~/.macguardian/threat_intel/` | IOC database and match history |
| `~/MacGuardian/quarantine/` | Files moved by remediation (not deleted) |

---

## Documentation

| File | Contents |
| ---- | -------- |
| [SECURITY.md](SECURITY.md) | Security policy, vulnerability reporting, sudo guide, app security features |
| [PRIVACY.md](PRIVACY.md) | Data collection, retention, and opt-out |
| [RELEASE.md](RELEASE.md) | Release process and versioning |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Hybrid SIEM/EDR architecture overview |
| [docs/BLUETEAM.md](docs/BLUETEAM.md) | Blue Team module details |
| [docs/AI_ML.md](docs/AI_ML.md) | AI and ML engine details |
| [docs/VERIFICATION_GUIDE.md](docs/VERIFICATION_GUIDE.md) | Testing and component verification |
| [docs/FEATURE_ROADMAP.md](docs/FEATURE_ROADMAP.md) | Planned features and gap analysis |
| [docs/FRAMEWORK_ALIGNMENT.md](docs/FRAMEWORK_ALIGNMENT.md) | MITRE ATT&CK / NIST framework mapping |
| [docs/TOOL_RECOMMENDATIONS.md](docs/TOOL_RECOMMENDATIONS.md) | Optional tool integrations |
| [docs/TERMINAL_GUIDE.md](docs/TERMINAL_GUIDE.md) | Terminal basics for new users |

---

## Security & Privacy

- All scan data stored locally — nothing sent externally except email reports you configure
- Passwords stored in macOS Keychain (never UserDefaults)
- File integrity verification runs on app startup for critical scripts
- All remediation dry-runs by default; quarantine instead of delete
- Rollback supported via JSON manifests with SHA-256 checksums

See [SECURITY.md](SECURITY.md) and [PRIVACY.md](PRIVACY.md) for full details.

---

## Built With

- [ClamAV](https://www.clamav.net/) — antivirus engine
- [rkhunter](http://rkhunter.sourceforge.net/) — rootkit detection
- [scikit-learn](https://scikit-learn.org/) — ML models
- [Homebrew](https://brew.sh/) — package management
- SwiftUI — native macOS interface

---

## License

MIT License — see [LICENSE](LICENSE) for details.
