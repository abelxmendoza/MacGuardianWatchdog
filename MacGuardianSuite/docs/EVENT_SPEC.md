# MacGuardian Event Specification v1.0.0

## Overview

This document defines the standard event format for all MacGuardian Watchdog modules. All watchers, auditors, detectors, and output modules must conform to this specification.

## Version

**v1.0.0** - Initial production release

## Event Structure

All events MUST be valid JSON objects with the following structure:

```json
{
  "event_id": "uuid4",
  "event_type": "string",
  "severity": "low|medium|high|critical",
  "timestamp": "ISO8601",
  "source": "module_name",
  "context": {
    ... module-specific data ...
  }
}
```

## Required Fields

### event_id
- **Type**: String (UUID v4)
- **Format**: `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`
- **Required**: Yes
- **Example**: `"550e8400-e29b-41d4-a716-446655440000"`
- **Validation**: Must match UUID v4 format

### event_type
- **Type**: String (enum)
- **Required**: Yes
- **Allowed Values**:
  - `process_anomaly`
  - `network_connection`
  - `dns_request`
  - `file_integrity_change`
  - `cron_modification`
  - `ssh_key_change`
  - `tcc_permission_change`
  - `user_account_change`
  - `signature_hit`
  - `ids_alert`
  - `privacy_event`
  - `ransomware_activity`
  - `persistence_change`
  - `config_change`
- **Example**: `"process_anomaly"`

### severity
- **Type**: String (enum)
- **Required**: Yes
- **Allowed Values**: `low`, `medium`, `high`, `critical`
- **Guidelines**:
  - `low`: Informational, normal operations
  - `medium`: Suspicious activity, requires review
  - `high`: Potential threat, immediate attention recommended
  - `critical`: Active threat, immediate action required
- **Example**: `"high"`

### timestamp
- **Type**: String (ISO 8601)
- **Format**: `YYYY-MM-DDTHH:MM:SS.sssZ` or `YYYY-MM-DDTHH:MM:SSZ`
- **Required**: Yes
- **Timezone**: UTC (Z suffix)
- **Example**: `"2024-01-15T10:30:45.123Z"`

### source
- **Type**: String
- **Required**: Yes
- **Description**: Module name that generated the event
- **Examples**: `"process_watcher"`, `"ssh_auditor"`, `"ids_engine"`
- **Validation**: Must match pattern: `^[a-z][a-z0-9_]*$`

### context
- **Type**: Object
- **Required**: Yes (can be empty object `{}`)
- **Description**: Module-specific data
- **Structure**: Varies by event type (see Event Type Specifications below)

## Event Type Specifications

### process_anomaly

```json
{
  "event_id": "...",
  "event_type": "process_anomaly",
  "severity": "high",
  "timestamp": "...",
  "source": "process_watcher",
  "context": {
    "pid": 12345,
    "process_name": "suspicious_app",
    "cpu_percent": 85.5,
    "memory_mb": 512,
    "command": "/path/to/app",
    "user": "username",
    "anomaly_type": "high_cpu|suspicious_pattern|hidden_process"
  }
}
```

### network_connection

```json
{
  "event_id": "...",
  "event_type": "network_connection",
  "severity": "medium",
  "timestamp": "...",
  "source": "network_watcher",
  "context": {
    "pid": 12345,
    "process_name": "curl",
    "local_ip": "192.168.1.100",
    "local_port": 54321,
    "remote_ip": "1.2.3.4",
    "remote_port": 80,
    "protocol": "tcp",
    "connection_state": "ESTABLISHED"
  }
}
```

### file_integrity_change

```json
{
  "event_id": "...",
  "event_type": "file_integrity_change",
  "severity": "medium",
  "timestamp": "...",
  "source": "fsevents_watcher",
  "context": {
    "file_path": "/path/to/file",
    "change_type": "modified|deleted|created|permission_changed",
    "old_hash": "sha256...",
    "new_hash": "sha256...",
    "directory": "/path/to/directory",
    "file_count": 15
  }
}
```

### persistence_change

A startup item (LaunchAgent, LaunchDaemon, StartupItem or shell profile) was added, modified or removed. Written by `persistence_watcher`, which also checks the code signature of the program the item runs.

```json
{
  "event_id": "...",
  "event_type": "persistence_change",
  "severity": "high",
  "timestamp": "...",
  "source": "persistence_watcher",
  "context": {
    "change_type": "added|modified|removed",
    "item_kind": "launchd|startupitem|profile",
    "path": "/Users/me/Library/LaunchAgents/com.example.agent.plist",
    "executable": "/Users/Shared/.hidden/agent",
    "signature_status": "apple|developer_id|app_store|adhoc|unsigned|invalid|missing|script|none",
    "signer": "Example Inc. (ABCDE12345)",
    "command": "/Users/Shared/.hidden/agent --daemon",
    "reasons": "program is unsigned; runs from a temporary, shared or hidden location"
  }
}
```

Severity: `low` for removals and items signed by a known developer; `medium` for scripts, ad-hoc signed Homebrew programs, missing programs and shell profile edits; `high` for unsigned, ad-hoc or invalid programs, risky locations, or commands that download or run inline code; `critical` when a `high` item is a LaunchDaemon (runs as root).

### cron_modification

```json
{
  "event_id": "...",
  "event_type": "cron_modification",
  "severity": "high",
  "timestamp": "...",
  "source": "cron_auditor",
  "context": {
    "user": "username",
    "job": "*/5 * * * * command",
    "change_type": "added|modified|deleted",
    "suspicious_pattern": "downloads_from_internet|obfuscated"
  }
}
```

### ssh_key_change

```json
{
  "event_id": "...",
  "event_type": "ssh_key_change",
  "severity": "high",
  "timestamp": "...",
  "source": "ssh_auditor",
  "context": {
    "file": "/Users/username/.ssh/authorized_keys",
    "change_type": "added|removed|modified",
    "key_fingerprint": "SHA256:...",
    "key_type": "rsa|ed25519|ecdsa"
  }
}
```

### tcc_permission_change

```json
{
  "event_id": "...",
  "event_type": "tcc_permission_change",
  "severity": "medium",
  "timestamp": "...",
  "source": "tcc_auditor",
  "context": {
    "app_bundle_id": "com.example.app",
    "service": "kTCCServiceFullDiskAccess",
    "allowed": true,
    "change_type": "granted|revoked"
  }
}
```

### user_account_change

```json
{
  "event_id": "...",
  "event_type": "user_account_change",
  "severity": "high",
  "timestamp": "...",
  "source": "user_account_auditor",
  "context": {
    "username": "newuser",
    "change_type": "added|removed|modified",
    "is_admin": true,
    "uid": 501,
    "gid": 20
  }
}
```

### ids_alert

```json
{
  "event_id": "...",
  "event_type": "ids_alert",
  "severity": "critical",
  "timestamp": "...",
  "source": "ids_engine",
  "context": {
    "rule_name": "Multiple Suspicious Activities",
    "correlated_events": ["event_id_1", "event_id_2"],
    "file_changes": 5,
    "new_processes": 2,
    "network_connections": 3,
    "time_window": 60
  }
}
```

### ransomware_activity

```json
{
  "event_id": "...",
  "event_type": "ransomware_activity",
  "severity": "critical",
  "timestamp": "...",
  "source": "ransomware_detector",
  "context": {
    "file_changes": 150,
    "encryption_patterns": 5,
    "time_window": 60,
    "affected_directories": ["/Users/username/Documents"]
  }
}
```

## Validation Rules

1. **Required Fields**: All required fields MUST be present
2. **Field Types**: Field types MUST match specification
3. **Enum Values**: Enum fields MUST use allowed values
4. **Timestamp Format**: Timestamps MUST be valid ISO 8601 UTC
5. **UUID Format**: event_id MUST be valid UUID v4
6. **JSON Validity**: Event MUST be valid JSON

## Backward Compatibility

- Future versions will maintain backward compatibility
- New optional fields may be added to `context`
- Required fields will not be removed
- Enum values may be extended but not removed

## Examples

### Minimal Valid Event

```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "event_type": "process_anomaly",
  "severity": "low",
  "timestamp": "2024-01-15T10:30:45Z",
  "source": "process_watcher",
  "context": {}
}
```

### Full Event

```json
{
  "event_id": "550e8400-e29b-41d4-a716-446655440000",
  "event_type": "ids_alert",
  "severity": "critical",
  "timestamp": "2024-01-15T10:30:45.123Z",
  "source": "ids_engine",
  "context": {
    "rule_name": "Multiple Suspicious Activities",
    "correlated_events": [
      "event-1-uuid",
      "event-2-uuid"
    ],
    "file_changes": 5,
    "new_processes": 2,
    "network_connections": 3,
    "time_window": 60
  }
}
```

## Implementation Notes

- All modules MUST validate events before emitting
- Event Bus MUST validate all incoming events
- Invalid events MUST be logged and rejected
- Events SHOULD be emitted as single-line JSON (JSONL format)
- Events MAY be batched for efficiency but MUST be parseable individually

## Version History

- **v1.0.0** (2024-01-15): Initial production release

