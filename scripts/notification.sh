#!/bin/bash
# Notification script for failover events
set -e

TITLE="$1"
MESSAGE="$2"
WEBHOOK_URL=${NOTIFICATION_WEBHOOK:-""}
LOG_FILE="/opt/failover-gateway/logs/notifications.log"

# Function to log messages
log_message() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $message" | tee -a $LOG_FILE
}

# Check if notifications are enabled
if [ "${ENABLE_NOTIFICATIONS}" != "true" ]; then
    log_message "Notifications are disabled. Skipping: $TITLE - $MESSAGE"
    exit 0
fi

# Create log file if it doesn't exist
mkdir -p $(dirname $LOG_FILE)
touch $LOG_FILE

# Log the notification
log_message "Sending notification: $TITLE - $MESSAGE"

# Send to webhook if configured
if [ -n "$WEBHOOK_URL" ]; then
    log_message "Sending to webhook: $WEBHOOK_URL"
    
    # Prepare JSON payload
    PAYLOAD=$(cat <<EOF
{
  "title": "$TITLE",
  "message": "$MESSAGE",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "service": "newt-tailscale-failover"
}
EOF
)
    
    # Send the webhook
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "$WEBHOOK_URL")
    
    if [ "$RESPONSE" = "200" ] || [ "$RESPONSE" = "201" ] || [ "$RESPONSE" = "202" ]; then
        log_message "Webhook sent successfully (HTTP $RESPONSE)"
    else
        log_message "Failed to send webhook notification (HTTP $RESPONSE)"
    fi
else
    log_message "No webhook URL configured, skipping webhook notification"
fi

# Log to the failover status file as well
STATUS_FILE="/opt/failover-gateway/status.json"
if [ -f "$STATUS_FILE" ]; then
    # Add notification to the notifications array in the status file
    NOTIFICATION="{\"time\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"title\":\"$TITLE\",\"message\":\"$MESSAGE\"}"
    
    # Use jq to update the file if it exists
    if command -v jq >/dev/null 2>&1; then
        if jq -e '.notifications' "$STATUS_FILE" >/dev/null 2>&1; then
            # notifications array exists, append to it
            jq --arg notif "$NOTIFICATION" '.notifications += [$notif | fromjson]' "$STATUS_FILE" > "$STATUS_FILE.tmp" && 
            mv "$STATUS_FILE.tmp" "$STATUS_FILE"
        else
            # notifications array doesn't exist, create it
            jq --arg notif "$NOTIFICATION" '. + {notifications: [$notif | fromjson]}' "$STATUS_FILE" > "$STATUS_FILE.tmp" && 
            mv "$STATUS_FILE.tmp" "$STATUS_FILE"
        fi
    fi
fi

exit 0