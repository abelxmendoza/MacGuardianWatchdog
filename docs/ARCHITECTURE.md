# 🏗️ MacGuardian Architecture: Hybrid SIEM/EDR Platform

## Overview

MacGuardian is designed as a **modular collector/agent** that can integrate with enterprise security stacks:

- **Collector/Agent**: MacGuardian (core)
- **SIEM Integration**: Splunk, ELK, custom dashboards
- **Network Monitoring**: Suricata, Zeek integration
- **Native Telemetry**: EndpointSecurity, FSEvents, Unified Logging

## Architecture Layers

```
┌─────────────────────────────────────────────────────────┐
│              Presentation Layer (Dashboards)              │
│  Splunk | ELK | Custom Web UI | Grafana | SIEM         │
└─────────────────────────────────────────────────────────┘
                          ▲
                          │ (REST API / Webhooks / Logs)
┌─────────────────────────────────────────────────────────┐
│              Intelligence Layer (Correlation)            │
│  Threat Intel | ML/AI | Rule Engine | Correlation      │
└─────────────────────────────────────────────────────────┘
                          ▲
                          │ (Events)
┌─────────────────────────────────────────────────────────┐
│              Collection Layer (MacGuardian Core)         │
│  Event Bus | Collectors | Normalization | Buffering      │
└─────────────────────────────────────────────────────────┘
                          ▲
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
┌───────▼──────┐  ┌───────▼──────┐  ┌───────▼──────┐
│  Endpoint   │  │   Network    │  │   File       │
│  Security   │  │   Monitoring │  │   Integrity  │
│  (macOS)    │  │  (Suricata)  │  │  (FSEvents)  │
└─────────────┘  └──────────────┘  └──────────────┘
```

## Core Components

### 1. Event Bus (Central Event System
- **Location**: `MacGuardianSuite/event_bus.py`
- **Purpose**: Central event routing and buffering
- **Features**:
  - Event queuing (in-memory + disk buffer)
  - Event normalization (common schema)
  - Event routing to modules
  - Backpressure handling
  - Event replay capability

### 2. Collector Modules

#### A. EndpointSecurity Collector
- **Location**: `MacGuardianSuite/collectors/endpoint_security.py`
- **Purpose**: Native macOS EndpointSecurity framework
- **Events**: Process execution, file access, network connections
- **Requirements**: System Extension, Full Disk Access

#### B. FSEvents Collector
- **Location**: `MacGuardianSuite/collectors/fsevents.py`
- **Purpose**: File system change monitoring
- **Events**: File create, modify, delete, rename
- **Advantages**: Event-driven (no polling), low overhead

#### C. Unified Logging Collector
- **Location**: `MacGuardianSuite/collectors/unified_logging.py`
- **Purpose**: macOS system logs via `log stream`
- **Events**: System events, security events, application logs
- **Advantages**: Native macOS logging, structured data

#### D. Network Collector
- **Location**: `MacGuardianSuite/collectors/network.py`
- **Purpose**: Network connection monitoring
- **Events**: Connection establish, data transfer, connection close
- **Integration**: Can feed Suricata/Zeek

### 3. Output Modules (SIEM Integration)

#### A. Splunk Output
- **Location**: `MacGuardianSuite/outputs/splunk.py`
- **Format**: HEC (HTTP Event Collector) JSON
- **Features**: Batch upload, retry logic, compression

#### B. ELK Stack Output
- **Location**: `MacGuardianSuite/outputs/elk.py`
- **Format**: Elasticsearch bulk API
- **Features**: Index management, mapping templates

#### C. Webhook Output
- **Location**: `MacGuardianSuite/outputs/webhook.py`
- **Format**: HTTP POST JSON
- **Features**: Custom endpoints, authentication

#### D. Local Storage
- **Location**: `MacGuardianSuite/outputs/local.py`
- **Format**: JSONL files, SQLite
- **Features**: Local buffering, query interface

## Event Schema

All events follow this structure:

```json
{
  "timestamp": "2024-11-08T12:34:56.789Z",
  "event_type": "process.exec",
  "source": "endpoint_security",
  "host": "macbook-pro.local",
  "user": "abel_elreaper",
  "data": {
    "pid": 12345,
    "ppid": 1,
    "path": "/usr/bin/python3",
    "args": ["-m", "http.server"],
    "uid": 501,
    "gid": 20
  },
  "metadata": {
    "severity": "info",
    "tags": ["process", "execution"],
    "correlation_id": "abc-123-def"
  }
}
```

## Module Interface

All modules implement a standard interface:

```python
class CollectorModule:
    def initialize(self, config):
        """Initialize the module with configuration"""
        pass
    
    def start(self):
        """Start collecting events"""
        pass
    
    def stop(self):
        """Stop collecting events"""
        pass
    
    def get_status(self):
        """Return module status"""
        pass
```

## Configuration

Modules are configured in `~/.macguardian/modules.conf`:

```ini
[collectors.endpoint_security]
enabled = true
buffer_size = 1000
filters = process.exec,file.write

[collectors.fsevents]
enabled = true
paths = /Users, /Applications, /System
exclude = .git, node_modules

[outputs.splunk]
enabled = true
url = https://splunk.example.com:8088
token = your-hec-token
index = macguardian
batch_size = 100

[outputs.elasticsearch]
enabled = false
url = http://localhost:9200
index = macguardian-%{+YYYY.MM.dd}
```

## Deployment Modes

### Mode 1: Lightweight (Standalone)
- Local collection only
- Local storage (JSONL, SQLite)
- Basic dashboards
- **Use case**: Personal use, single machine

### Mode 2: Hybrid (Recommended)
- Local collection + buffering
- Periodic export to SIEM
- Local query interface
- **Use case**: Small business, multiple machines

### Mode 3: Full SIEM Integration
- Real-time streaming
- Centralized storage
- Enterprise dashboards
- **Use case**: Enterprise, SOC operations

## Performance Considerations

- **Event Rate**: 1000-10,000 events/second
- **Buffer Size**: Configurable (default: 10,000 events)
- **Batch Upload**: 100-1000 events per batch
- **Compression**: Gzip for network transport
- **Backpressure**: Disk buffering when network slow

## Security

- **TLS**: All network connections use TLS
- **Authentication**: Token-based for SIEM
- **Encryption**: At-rest encryption for local buffers
- **Permissions**: Minimal required macOS permissions
- **Audit**: All module actions logged

## Next Steps

1. **Start Lightweight**: Enable local collectors only
2. **Add Network Monitoring**: Integrate Suricata/Zeek
3. **Add SIEM Output**: Configure Splunk/ELK
4. **Scale Up**: Add more collectors, expand filtering

