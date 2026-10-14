#!/usr/bin/env python3

"""
MacGuardian Event Bus
Central hub for all real-time events with WebSocket support
"""

import json
import sys
import os
import asyncio
try:
    # Optional: only needed for the WebSocket broadcast server. The in-process
    # bus (used by module_manager.py) and the Unix socket work without it.
    import websockets
except ImportError:
    websockets = None
import socket
import uuid
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, asdict
import signal

# Configuration
EVENT_DIR = Path.home() / ".macguardian" / "events"
LOG_DIR = Path.home() / ".macguardian" / "logs"
UDS_SOCKET = "/tmp/macguardian.sock"
WS_PORT = 9765
WS_HOST = "localhost"
MAX_EVENTS_CACHE = 1000

# Ensure directories exist
EVENT_DIR.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)

@dataclass
class Event:
    """Event Spec v1.0.0 compliant event structure"""
    event_id: str
    timestamp: str
    type: str  # Event Spec v1.0.0 event_type
    severity: str  # low, medium, high, critical
    source: str  # process_watcher, network_watcher, etc.
    message: str
    context: Dict[str, Any]
    
    def to_json(self) -> str:
        """Convert to Event Spec v1.0.0 JSON format"""
        event_dict = {
            "event_id": self.event_id,
            "event_type": self.type,
            "severity": self.severity,
            "timestamp": self.timestamp,
            "source": self.source,
            "context": {**self.context, "message": self.message} if self.message else self.context
        }
        return json.dumps(event_dict)
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Event':
        """Create Event from dictionary (Event Spec v1.0.0)"""
        event_id = data.get('event_id') or data.get('id') or str(uuid.uuid4())
        context = data.get('context', {})
        message = context.get('message', data.get('message', ''))
        return cls(
            event_id=event_id,
            timestamp=data.get('timestamp', datetime.utcnow().isoformat() + 'Z'),
            type=data.get('event_type') or data.get('type', 'process_anomaly'),
            severity=data.get('severity', 'medium'),
            source=data.get('source', 'unknown'),
            message=message,
            context=context
        )

class EventBus:
    """Central event bus for MacGuardian"""
    
    def __init__(self):
        self.event_cache: List[Event] = []
        self.websocket_clients: set = set()
        self.running = True
        
    def normalize_event(self, raw_data: Dict[str, Any]) -> Event:
        """Normalize event to Event Spec v1.0.0 format"""
        # Event Spec v1.0.0 required fields
        event_id = raw_data.get('event_id') or raw_data.get('id')
        if not event_id:
            event_id = str(uuid.uuid4())
        
        timestamp = raw_data.get('timestamp', datetime.utcnow().isoformat() + 'Z')
        event_type = raw_data.get('event_type') or raw_data.get('type', 'process_anomaly')
        severity = raw_data.get('severity', 'medium')
        source = raw_data.get('source', self._infer_source(event_type))
        context = raw_data.get('context', {})
        
        # Validate Event Spec v1.0.0 compliance
        if not self._validate_event_spec(event_id, event_type, severity, timestamp):
            # Log validation error but don't fail
            print(f"WARNING: Event validation failed for event_id: {event_id}", file=sys.stderr)
        
        # Extract message from context if present
        message = context.get('message', raw_data.get('message', ''))
        
        return Event(
            event_id=event_id,
            timestamp=timestamp,
            type=event_type,
            severity=severity,
            source=source,
            message=message,
            context=context
        )
    
    def _validate_event_spec(self, event_id: str, event_type: str, severity: str, timestamp: str) -> bool:
        """Validate Event Spec v1.0.0 compliance"""
        import re
        
        # Validate UUID format
        uuid_pattern = r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        if not re.match(uuid_pattern, event_id.lower()):
            return False
        
        # Validate event_type enum
        valid_types = [
            'process_anomaly', 'network_connection', 'dns_request',
            'file_integrity_change', 'cron_modification', 'ssh_key_change',
            'tcc_permission_change', 'user_account_change', 'signature_hit',
            'ids_alert', 'privacy_event', 'ransomware_activity', 'config_change'
        ]
        if event_type not in valid_types:
            return False
        
        # Validate severity enum
        if severity not in ['low', 'medium', 'high', 'critical']:
            return False
        
        # Validate ISO8601 timestamp
        iso8601_pattern = r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z?$'
        if not re.match(iso8601_pattern, timestamp):
            return False
        
        return True
    
    def _infer_source(self, event_type: str) -> str:
        """Infer source from Event Spec v1.0.0 event type"""
        # Event Spec v1.0.0 event types to source mapping
        source_map = {
            'file_integrity_change': 'fsevents_watcher',
            'process_anomaly': 'process_watcher',
            'network_connection': 'network_watcher',
            'dns_request': 'network_watcher',
            'ids_alert': 'ids_engine',
            'ssh_key_change': 'ssh_auditor',
            'user_account_change': 'user_account_auditor',
            'cron_modification': 'cron_auditor',
            'tcc_permission_change': 'tcc_auditor',
            'privacy_event': 'tcc_auditor',
            'ransomware_activity': 'ransomware_detector',
            'signature_hit': 'signature_engine',
            'config_change': 'config_manager'
        }
        # Also support legacy types for backward compatibility
        legacy_map = {
            'filesystem': 'fsevents_watcher',
            'fs': 'fsevents_watcher',
            'process': 'process_watcher',
            'network': 'network_watcher',
            'ids': 'ids_engine',
            'correlation': 'ids_engine',
            'ssh': 'ssh_auditor',
            'user_accounts': 'user_account_auditor',
            'cron': 'cron_auditor',
            'tcc_privacy': 'tcc_auditor',
            'privacy': 'tcc_auditor',
            'ransomware': 'ransomware_detector',
            'signature': 'signature_engine'
        }
        return source_map.get(event_type) or legacy_map.get(event_type, 'unknown')
    
    def store_event(self, event: Event):
        """Store event to disk"""
        event_file = EVENT_DIR / f"event_{datetime.utcnow().strftime('%Y%m%d_%H%M%S_%f')}.json"
        try:
            with open(event_file, 'w') as f:
                json.dump(asdict(event), f, indent=2)
        except IOError as e:
            print(f"Error storing event: {e}", file=sys.stderr)
    
    def add_event(self, raw_data: Dict[str, Any]):
        """Add and broadcast event"""
        event = self.normalize_event(raw_data)
        
        # Store to disk
        self.store_event(event)
        
        # Add to cache
        self.event_cache.append(event)
        if len(self.event_cache) > MAX_EVENTS_CACHE:
            self.event_cache.pop(0)
        
        # Broadcast to WebSocket clients
        asyncio.create_task(self.broadcast_event(event))
    
    async def broadcast_event(self, event: Event):
        """Broadcast event to all connected WebSocket clients"""
        if not self.websocket_clients:
            return
        
        message = event.to_json()
        disconnected = set()
        
        for client in self.websocket_clients:
            try:
                await client.send(message)
            except Exception as e:
                if websockets is None or not isinstance(e, websockets.exceptions.ConnectionClosed):
                    print(f"Error broadcasting to client: {e}", file=sys.stderr)
                disconnected.add(client)
        
        # Remove disconnected clients
        self.websocket_clients -= disconnected
    
    async def handle_websocket(self, websocket, path):
        """Handle WebSocket connection"""
        self.websocket_clients.add(websocket)
        print(f"WebSocket client connected: {websocket.remote_address}")
        
        try:
            # Send recent events on connect
            recent_events = self.event_cache[-100:]  # Last 100 events
            for event in recent_events:
                await websocket.send(event.to_json())
            
            # Keep connection alive
            await websocket.wait_closed()
        except Exception:
            pass  # client went away
        finally:
            self.websocket_clients.discard(websocket)
            print(f"WebSocket client disconnected: {websocket.remote_address}")
    
    async def handle_uds_client(self, reader, writer):
        """Handle Unix Domain Socket client (from shell scripts)"""
        try:
            data = await reader.read(4096)
            if not data:
                return
            
            # Parse JSON from shell script
            try:
                raw_event = json.loads(data.decode('utf-8'))
                self.add_event(raw_event)
            except json.JSONDecodeError as e:
                print(f"Invalid JSON from UDS client: {e}", file=sys.stderr)
        except Exception as e:
            print(f"Error handling UDS client: {e}", file=sys.stderr)
        finally:
            writer.close()
            await writer.wait_closed()
    
    async def start_uds_server(self):
        """Start Unix Domain Socket server"""
        # Remove existing socket
        if os.path.exists(UDS_SOCKET):
            os.unlink(UDS_SOCKET)
        
        server = await asyncio.start_unix_server(
            self.handle_uds_client,
            UDS_SOCKET
        )
        
        # Only this user may connect; anyone who can write to the socket can
        # inject security events.
        os.chmod(UDS_SOCKET, 0o600)
        
        print(f"UDS server listening on {UDS_SOCKET}")
        async with server:
            await server.serve_forever()
    
    async def start_websocket_server(self):
        """Start WebSocket server"""
        if websockets is None:
            print("WebSocket server disabled (pip install websockets to enable)", file=sys.stderr)
            return
        async with websockets.serve(self.handle_websocket, WS_HOST, WS_PORT):
            print(f"WebSocket server listening on ws://{WS_HOST}:{WS_PORT}")
            await asyncio.Future()  # Run forever
    
    async def run(self):
        """Run event bus"""
        print("🚀 MacGuardian Event Bus starting...")
        print(f"Event directory: {EVENT_DIR}")
        print(f"UDS socket: {UDS_SOCKET}")
        print(f"WebSocket: ws://{WS_HOST}:{WS_PORT}")
        
        # Run both servers concurrently
        await asyncio.gather(
            self.start_uds_server(),
            self.start_websocket_server()
        )

def signal_handler(signum, frame):
    """Handle shutdown signals"""
    print("\n🛑 Shutting down Event Bus...")
    sys.exit(0)

def main():
    """Main entry point"""
    # Install signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Create and run event bus
    bus = EventBus()
    
    try:
        asyncio.run(bus.run())
    except KeyboardInterrupt:
        print("\n🛑 Event Bus stopped")
    except Exception as e:
        print(f"Error running event bus: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()

