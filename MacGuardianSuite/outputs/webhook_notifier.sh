#!/bin/bash

# ===============================
# Webhook Notifier
# Sends alerts to webhooks (Slack, Discord, Teams, etc.)
# ===============================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SUITE_DIR/utils.sh" 2>/dev/null || true

WEBHOOK_URL="${WEBHOOK_URL:-}"
WEBHOOK_TYPE="${WEBHOOK_TYPE:-generic}"  # slack, discord, teams, generic

# Send webhook notification
send_webhook() {
    local title="$1"
    local message="$2"
    local severity="${3:-info}"
    local details="${4:-{}}"
    
    if [ -z "$WEBHOOK_URL" ]; then
        warning "Webhook URL not configured"
        return 1
    fi
    
    if ! command -v curl &> /dev/null; then
        warning "curl not available - cannot send webhook"
        return 1
    fi
    
    local payload=""
    
    case "$WEBHOOK_TYPE" in
        slack)
            payload=$(cat <<EOF
{
  "text": "$title",
  "attachments": [
    {
      "color": "$(get_slack_color "$severity")",
      "text": "$message",
      "fields": [
        {
          "title": "Severity",
          "value": "$severity",
          "short": true
        }
      ]
    }
  ]
}
EOF
)
            ;;
        discord)
            payload=$(cat <<EOF
{
  "embeds": [
    {
      "title": "$title",
      "description": "$message",
      "color": $(get_discord_color "$severity"),
      "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    }
  ]
}
EOF
)
            ;;
        *)
            # Generic JSON
            payload=$(cat <<EOF
{
  "title": "$title",
  "message": "$message",
  "severity": "$severity",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "details": $details
}
EOF
)
            ;;
    esac
    
    # Send webhook
    if curl -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        --silent --show-error --fail-with-body > /dev/null 2>&1; then
        success "Webhook notification sent"
        return 0
    else
        warning "Failed to send webhook notification"
        return 1
    fi
}

# Get Slack color
get_slack_color() {
    case "$1" in
        critical) echo "danger" ;;
        high) echo "warning" ;;
        medium) echo "good" ;;
        *) echo "good" ;;
    esac
}

# Get Discord color (decimal)
get_discord_color() {
    case "$1" in
        critical) echo "15158332" ;;  # Red
        high) echo "16776960" ;;      # Yellow
        medium) echo "3447003" ;;     # Blue
        *) echo "3066993" ;;          # Green
    esac
}

# Main execution
if [ $# -ge 2 ]; then
    send_webhook "$1" "$2" "${3:-info}" "${4:-{}}"
else
    echo "Usage: webhook_notifier.sh <title> <message> [severity] [details_json]"
    exit 1
fi

