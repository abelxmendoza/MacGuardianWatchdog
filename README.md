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

- **Antivirus & Rootkit Scanning** via ClamAV and rkhunter
- **File Integrity Monitoring** — SHA-256 baseline + change detection
- **Real-Time Threat Monitor** — live event stream via WebSocket from local daemon
- **Threat Intelligence** — IOC matching against Abuse.ch Feodo, URLhaus, and Malware Domain List feeds, with persistent match history
- **Blue Team Dashboard** — process analysis, network monitoring, behavioral anomaly detection
- **Omega Guardian Alert System** — rule-based incident engine with throttling and persistent incident store
- **Security Audit** — posture assessment with pass/fail checks and real security score
- **Automated Remediation** — dry-run preview before any change, quarantine instead of delete
- **Cache Cleaner** — browser (Safari, Chrome, Firefox, Edge) + system + Homebrew caches
- **Process Killer** — force-quit stubborn apps
- **SSH Security, User Account, Privacy, Network Graph, Incident Timeline** dashboards

All data stays local. Nothing is sent to external servers except optional email reports you configure.

---

## Requirements

| Component | Minimum |
| --------- | ------- |
| macOS (SwiftUI app) | 14.0 (Sonoma) |
| macOS (shell scripts) | 12.0 (Monterey) |
| Swift | 5.9+ |
| Homebrew | Any recent version |

Install Xcode Command Line Tools if not present:

```bash
xcode-select --install
```

---

## Quick Start

### Option A — Native App (Recommended)

```bash
git clone https://github.com/abelxmendoza/MacGuardianWachdog.git
cd MacGuardianWachdog/MacGuardianSuiteUI
swift build -c release
```

Copy the built app to Applications:

```bash
cp -r .build/MacGuardian\ Suite.app /Applications/
```

Then launch **MacGuardian Suite** from Spotlight, Applications, or the Dock.

First-time setup:

1. The app defaults to `~/Desktop/MacGuardianProject` — click the folder icon in the sidebar if your path is different
2. Toggle **Safe Mode** on (adds confirmation dialogs before destructive operations)
3. Optionally configure email in Settings for report delivery

### Option B — Command Line

```bash
git clone https://github.com/abelxmendoza/MacGuardianWachdog.git
cd MacGuardianWachdog
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

### mac_ai.sh / ai_engine.py / ml_engine.py — ML Analysis

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

Install launchd jobs to run scans automatically:

```bash
./MacGuardianSuite/install_scheduler.sh
```

Default schedule:

- **Daily at 2:00 AM** — Mac Watchdog (file integrity)
- **Sundays at 3:00 AM** — Mac Guardian (full security scan)
- **Daily at 9:00 AM** — Security report generation

---

## Recent Changes

### Security & Data Integrity Fixes

- **Threat match persistence** — `ThreatMatch` is now `Codable`; match history survives app restarts. `loadThreatMatches` and `saveThreatMatches` are fully implemented.
- **Alert engine IOC matching** — `iocMatch` condition now only fires when `event.category` is an actual IOC type (ip, domain, hash, url, file\_path). Previously it fired on any medium+ severity event regardless of type.
- **Alert engine completeness** — `processEvent` now returns all matching rule incidents, not just the first match.

### Dashboard

- **Security score** — calculated from real scan exit codes (exit 0 = clean, exit 1 = threat found) and IOC match count. No longer a hardcoded 85% default. Shows "Run a scan to get your score" when no data exists.
- **System Health card** — runs live checks on every load: firewall (`socketfilterfw`), FileVault (`fdesetup`), ClamAV presence (`which clamscan`), Time Machine backup (`tmutil latestbackup`). No longer hardcoded.
- **Dashboard decluttered** — removed redundant quick-access cards for Process Killer, Cache Cleaner, and Cursor Cache Cleaner. System Health moved to top.

### Cache Cleaner

- **Homebrew cache size** now reads from `~/Library/Caches/Homebrew` (the actual location). Previously checked `/opt/homebrew/var/cache` which always returned 0.
- Close buttons added to Cache Cleaner and Cursor Cache Cleaner sheets.

### Code Cleanup

- Removed `SecurityStatusCard` — was always hardcoded green, never checked anything real.
- Removed unreachable `SecurityScoreView` — no tab routed to it and all score values were hardcoded.
- Removed duplicate `openPanel()` function in `ContentView` (identical to `openPathPicker()`).
- Removed unused `showThreatIntelligence` bool from `WorkspaceState`.
- Removed redundant "Copy & Open Terminal" rootkit button from `SecurityDashboardView`.

---

## Troubleshooting

### App won't launch

- Verify macOS 14.0+: `sw_vers`
- Verify Xcode tools: `xcode-select -p`
- Rebuild: `cd MacGuardianSuiteUI && swift build -c release`

### Scripts not found

- Set the repository path in the app sidebar (folder icon)
- Ensure scripts are executable: `chmod +x MacGuardianSuite/*.sh`

### Real-time monitor shows disconnected

- The event daemon must be running: `python3 MacGuardianSuite/event_bus.py`
- The app connects to `ws://localhost:9765`

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
