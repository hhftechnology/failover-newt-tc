#!/bin/bash
# Failover monitoring script for Newt-Tailscale Failover Gateway
set -e

# Configuration
HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-10}
HEALTH_CHECK_TIMEOUT=${HEALTH_CHECK_TIMEOUT:-5}
HEALTH_CHECK_FAILURES_THRESHOLD=${HEALTH_CHECK_FAILURES_THRESHOLD:-3}
HEALTH_CHECK_RECOVERY_THRESHOLD=${HEALTH_CHECK_RECOVERY_THRESHOLD:-5}
FAILOVER_MODE=${FAILOVER_MODE:-immediate}
PRIMARY_SERVICE=${PRIMARY_SERVICE:-newt}
ENABLE_NOTIFICATIONS=${ENABLE_NOTIFICATIONS:-false}
LOG_FILE="/opt/failover-gateway/logs/failover.log"

# Initialize state
ACTIVE_SERVICE=$PRIMARY_SERVICE
CONSECUTIVE_FAILURES=0
CONSECUTIVE_RECOVERIES=0
FAILOVER_ACTIVE=false
LAST_FAILOVER_TIME=""

# Create status file
STATUS_FILE="/opt/failover-gateway/status.json"
echo "{\"active_service\":\"$ACTIVE_SERVICE\",\"primary_service\":\"$PRIMARY_SERVICE\",\"failover_active\":false,\"last_failover\":null,\"health\":{\"newt\":\"unknown\",\"tailscale\":\"unknown\"}}" > $STATUS_FILE

# Initialize log file
mkdir -p $(dirname $LOG_FILE)
echo "[$(date +%Y-%m-%d\ %H:%M:%S)] Failover monitor started. Primary service: $PRIMARY_SERVICE" > $LOG_FILE

# Function to log messages
log_message() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $message" | tee -a $LOG_FILE
}

# Function to update status file
update_status() {
    local newt_health="$1"
    local tailscale_health="$2"
    
    # Create a temporary JSON object with the failover status
    local failover_json="false"
    if [ "$FAILOVER_ACTIVE" = "true" ]; then
        failover_json="true"
    fi
    
    # Use proper jq syntax without the invalid --arb option
    jq --arg active "$ACTIVE_SERVICE" \
       --arg primary "$PRIMARY_SERVICE" \
       --arg failover "$failover_json" \
       --arg last "$LAST_FAILOVER_TIME" \
       --arg newt_health "$newt_health" \
       --arg tailscale_health "$tailscale_health" \
       '.active_service = $active | .primary_service = $primary | .failover_active = ($failover == "true") | .last_failover = $last | .health.newt = $newt_health | .health.tailscale = $tailscale_health' \
       $STATUS_FILE > $STATUS_FILE.tmp && mv $STATUS_FILE.tmp $STATUS_FILE
}

# Function to check if Newt is healthy
check_newt_health() {
    local timeout=$HEALTH_CHECK_TIMEOUT
    
    # First check if newt process is running
    if ! pgrep -f newt > /dev/null; then
        log_message "Newt process is not running"
        return 1
    fi
    
    # Check if newt has an active connection (implementation depends on newt's status API)
    # This is a simplified check and may need to be adapted based on Newt's actual behavior
    if ! timeout $timeout /usr/local/bin/health-check.sh newt; then
        log_message "Newt health check failed"
        return 1
    fi
    
    return 0
}

# Function to check if Tailscale is healthy
check_tailscale_health() {
    local timeout=$HEALTH_CHECK_TIMEOUT
    
    # Check if tailscale is running
    if ! pgrep -f tailscaled > /dev/null; then
        log_message "Tailscaled process is not running"
        return 1
    fi
    
    # Check if tailscale has an active connection
    if ! timeout $timeout tailscale status --json | jq -e '.BackendState == "Running"' > /dev/null; then
        log_message "Tailscale is not in Running state"
        return 1
    fi
    
    # Check if we can reach the tailscale network
    if ! timeout $timeout ping -c 1 100.100.100.100 > /dev/null 2>&1; then
        log_message "Cannot ping Tailscale network"
        return 1
    fi
    
    return 0
}

# Function to trigger failover to Tailscale
trigger_failover_to_tailscale() {
    if [ "$FAILOVER_ACTIVE" = "true" ]; then
        log_message "Failover already active, skipping"
        return
    fi
    
    log_message "Triggering failover from Newt to Tailscale"
    LAST_FAILOVER_TIME=$(date +"%Y-%m-%d %H:%M:%S")
    FAILOVER_ACTIVE=true
    ACTIVE_SERVICE="tailscale"
    
    # Execute the failover switch script
    /usr/local/bin/failover-switch.sh $FAILOVER_MODE newt tailscale
    
    # Send notification if enabled
    if [ "$ENABLE_NOTIFICATIONS" = "true" ]; then
        /usr/local/bin/notification.sh "Failover Alert" "Newt service is down. Traffic switched to Tailscale at $LAST_FAILOVER_TIME"
    fi
    
    # Update status
    update_status "down" "up"
}

# Function to recover back to Newt
trigger_recovery_to_newt() {
    if [ "$FAILOVER_ACTIVE" = "false" ]; then
        log_message "No active failover, skipping recovery"
        return
    fi
    
    log_message "Recovering from failover, switching back to Newt"
    FAILOVER_ACTIVE=false
    ACTIVE_SERVICE="newt"
    
    # Execute the failover switch script in reverse
    /usr/local/bin/failover-switch.sh $FAILOVER_MODE tailscale newt
    
    # Send notification if enabled
    if [ "$ENABLE_NOTIFICATIONS" = "true" ]; then
        /usr/local/bin/notification.sh "Recovery Alert" "Newt service is back online. Traffic switched back from Tailscale at $(date +"%Y-%m-%d %H:%M:%S")"
    fi
    
    # Update status
    update_status "up" "standby"
}

# Main monitoring loop
log_message "Starting failover monitoring. Primary service: $PRIMARY_SERVICE"
log_message "Health check interval: ${HEALTH_CHECK_INTERVAL}s, Failure threshold: $HEALTH_CHECK_FAILURES_THRESHOLD, Recovery threshold: $HEALTH_CHECK_RECOVERY_THRESHOLD"

while true; do
    # Check health of both services
    if check_newt_health; then
        NEWT_HEALTH="up"
        # If Newt is the primary and it's healthy, increment recovery counter
        if [ "$PRIMARY_SERVICE" = "newt" ] && [ "$FAILOVER_ACTIVE" = "true" ]; then
            CONSECUTIVE_RECOVERIES=$((CONSECUTIVE_RECOVERIES + 1))
            log_message "Newt is healthy. Recovery count: $CONSECUTIVE_RECOVERIES/$HEALTH_CHECK_RECOVERY_THRESHOLD"
            
            # Check if we've reached the recovery threshold to switch back
            if [ $CONSECUTIVE_RECOVERIES -ge $HEALTH_CHECK_RECOVERY_THRESHOLD ]; then
                trigger_recovery_to_newt
                CONSECUTIVE_RECOVERIES=0
                CONSECUTIVE_FAILURES=0
            fi
        else
            CONSECUTIVE_FAILURES=0
        fi
    else
        NEWT_HEALTH="down"
        # If Newt is the primary and it's unhealthy, increment failure counter
        if [ "$PRIMARY_SERVICE" = "newt" ] && [ "$FAILOVER_ACTIVE" = "false" ]; then
            CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
            log_message "Newt is unhealthy. Failure count: $CONSECUTIVE_FAILURES/$HEALTH_CHECK_FAILURES_THRESHOLD"
            
            # Check if we've reached the failure threshold to trigger failover
            if [ $CONSECUTIVE_FAILURES -ge $HEALTH_CHECK_FAILURES_THRESHOLD ]; then
                trigger_failover_to_tailscale
                CONSECUTIVE_FAILURES=0
                CONSECUTIVE_RECOVERIES=0
            fi
        fi
    fi
    
    # Check Tailscale health
    if check_tailscale_health; then
        TAILSCALE_HEALTH="up"
    else
        TAILSCALE_HEALTH="down"
        log_message "Warning: Tailscale is unhealthy. Failover may not work properly."
    fi
    
    # Update status file with current health status
    update_status $NEWT_HEALTH $TAILSCALE_HEALTH
    
    # Sleep before next check
    sleep $HEALTH_CHECK_INTERVAL
done