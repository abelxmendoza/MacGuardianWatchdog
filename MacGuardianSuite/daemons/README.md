# MacGuardian Real-Time Monitoring Daemon

## Overview

The MacGuardian Real-Time Monitoring Daemon provides continuous background security monitoring for macOS systems. It detects security events in real-time and writes structured JSON events that can be visualized in the SwiftUI application.

## Architecture

```
MacGuardianSuite/daemons/
├── macguardian_monitor.sh    # Main event loop daemon
├── event_writer.sh            # JSON event writer
├── fsevents_watcher.sh        # File system change detection
├── process_watcher.sh         # Process anomaly detection
├── network_watcher.sh         # Network connection monitoring
└── persistence_watcher.sh     # Startup item and code-signing monitoring
```

## Features

### Real-Time File System Monitoring
- Monitors critical directories (`~/Documents`, `~/Downloads`, `~/Desktop`, `~/.ssh`)
- Detects multiple file changes (>5 files)
- Identifies suspicious file types (.exe, .bat, .scr, .vbs, .ps1, .sh)
- Uses efficient timestamp-based change detection

### Real-Time Process Monitoring
- Tracks process count changes (>50% deviation from baseline)
- Detects high CPU processes (>80% CPU usage)
- Identifies suspicious process patterns (curl, nc, nmap, python3, osascript)
- Flags processes with malicious names (miner, crypto, bitcoin, malware, trojan, backdoor, keylogger)

### Real-Time Network Monitoring
- Monitors established network connections
- Detects connections to suspicious ports (4444, 5555, 6666, 7777, 8888, 9999, 1337, 31337)
- Checks connections against threat intelligence database
- Identifies unexpected listening ports
- Detects suspicious internal network connections

### Real-Time Persistence Monitoring
- Watches LaunchAgents, LaunchDaemons, StartupItems and shell profiles (`~/.zshrc`, `/etc/zprofile`, ...)
- Checks the code signature of whatever each item runs (Apple, Developer ID, App Store, ad-hoc, unsigned, invalid, missing)
- Raises `persistence_change` events for added, modified and removed items; unsigned programs, hidden or temporary locations and download-and-run commands are `high`, and `critical` for LaunchDaemons (root)
- Only runs the full codesign pass when a watched file or program actually changed
- `persistence_watcher.sh scan` lists every startup item with its signer, like KnockKnock

## Installation

```bash
cd MacGuardianSuite
./install_monitor_daemon.sh
```

This will:
1. Create the LaunchAgent plist file
2. Load the daemon into launchd
3. Start monitoring automatically

## Event Storage

Events are stored as JSON files in `~/.macguardian/events/`:

```json
{
  "id": "event-uuid",
  "timestamp": "2024-01-15T10:30:00Z",
  "type": "filesystem|process|network|system",
  "severity": "info|low|medium|high|critical",
  "message": "Human-readable message",
  "details": {
    "pid": 1234,
    "process": "suspicious_app",
    "cpu_percent": 85.5,
    ...
  }
}
```

## Logging

Daemon logs are written to:
- Standard output: `~/.macguardian/logs/monitor.out`
- Standard error: `~/.macguardian/logs/monitor.err`
- Monitor log: `~/.macguardian/logs/monitor.log`

## Management

### Check Status
```bash
launchctl list | grep macguardian.monitor
```

### Stop Daemon
```bash
launchctl unload ~/Library/LaunchAgents/com.macguardian.monitor.plist
```

### Start Daemon
```bash
launchctl load ~/Library/LaunchAgents/com.macguardian.monitor.plist
```

### Uninstall
```bash
./install_monitor_daemon.sh --uninstall
```

## SwiftUI Integration

The `RealTimeMonitorService` class reads events from `~/.macguardian/events/` and updates the `RealTimeDashboardView` in real-time.

### Usage in SwiftUI

```swift
@StateObject private var monitorService = RealTimeMonitorService()

// Start monitoring
monitorService.startMonitoring()

// Access events
let events = monitorService.events
let criticalEvents = monitorService.criticalEvents
```

## Performance Considerations

- Main loop runs every 3 seconds
- Process checks run every 30 seconds
- Network checks run every 60 seconds
- File system checks use efficient timestamp comparison
- Events are limited to prevent disk space issues

## Security

- Event files are created with `chmod 600` (owner read/write only)
- No sensitive data is logged
- Process monitoring excludes known system processes
- Network monitoring only checks connection metadata (no packet inspection)

## Troubleshooting

### Daemon Not Starting
1. Check logs: `tail -f ~/.macguardian/logs/monitor.err`
2. Verify script permissions: `chmod +x MacGuardianSuite/daemons/*.sh`
3. Check LaunchAgent: `launchctl list | grep macguardian.monitor`

### No Events Generated
1. Verify event directory exists: `ls -la ~/.macguardian/events/`
2. Check daemon is running: `ps aux | grep macguardian_monitor`
3. Review monitor log: `tail -f ~/.macguardian/logs/monitor.log`

### High CPU Usage
- Adjust sleep interval in `macguardian_monitor.sh` (default: 3 seconds)
- Increase check intervals in watcher scripts
- Reduce number of watched directories

## Configuration

Edit the watcher scripts to customize:
- Watched directories (`fsevents_watcher.sh`)
- Process check intervals (`process_watcher.sh`)
- Network check intervals (`network_watcher.sh`)
- Suspicious port lists (`network_watcher.sh`)

## Future Enhancements

- [ ] FSEvents API integration for true real-time file monitoring
- [ ] Endpoint Detection and Response (EDR) capabilities
- [ ] Machine learning-based anomaly detection
- [ ] Integration with macOS Unified Logging
- [ ] Webhook notifications for critical events
- [ ] Event correlation and threat intelligence enrichment

