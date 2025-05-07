#!/bin/bash
# Health check script for Newt and Tailscale services
set -e

SERVICE=$1
TIMEOUT=${HEALTH_CHECK_TIMEOUT:-5}

# Function to check Newt health
check_newt() {
    # Check if Newt process is running
    if ! pgrep -f newt > /dev/null; then
        echo "Newt process is not running"
        return 1
    fi
    
    # Check Newt tunnel connectivity by pinging the gateway
    # Using the same IP that Newt itself is trying to ping (100.89.128.1)
    if ping -c 1 -W "$TIMEOUT" 100.89.128.1 >/dev/null 2>&1; then
        # If we can ping the gateway, the tunnel is working
        return 0
    fi
    
    # Alternatively, try to connect to a service via the Newt tunnel
    # This depends on your network setup and what's accessible through Newt
    # Replace TARGET_IP with an actual IP on your private network
    local TARGET_IP=$(getent hosts app | awk '{ print $1 }')
    if [ -n "$TARGET_IP" ] && nc -z -w "$TIMEOUT" "$TARGET_IP" 80 >/dev/null 2>&1; then
        return 0
    fi
    
    echo "Cannot establish connectivity through Newt tunnel"
    return 1
}

# Function to check Tailscale health
check_tailscale() {
    # Check if tailscaled is running
    if ! pgrep -f tailscaled > /dev/null; then
        echo "Tailscaled process is not running"
        return 1
    fi
    
    # Check if we have an active Tailscale connection
    if ! tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' > /dev/null; then
        echo "Tailscale is not in Running state"
        return 1
    fi
    
    # Check if we can reach the Tailscale network
    # Try to ping a known Tailscale address like the MagicDNS server
    if ! ping -c 1 -W "$TIMEOUT" 100.100.100.100 >/dev/null 2>&1; then
        echo "Cannot ping Tailscale network"
        return 1
    fi
    
    return 0
}

# Execute the appropriate health check
case "$SERVICE" in
    newt)
        check_newt
        ;;
    tailscale)
        check_tailscale
        ;;
    *)
        echo "Error: Unknown service $SERVICE. Use 'newt' or 'tailscale'."
        exit 1
        ;;
esac

# Return the result of the health check
exit $?