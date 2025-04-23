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
    
    # Check if Newt has a working connection
    # This will need to be customized based on how Newt can be checked
    # For example, we could check if a test request can be made through Newt
    
    # Check if we can connect to a test endpoint via Newt
    # This is a simplified example - actual implementation will depend on Newt's behavior
    # We'll try to connect to the app service via Newt
    if nc -z -w "$TIMEOUT" localhost 80 >/dev/null 2>&1; then
        # If we can connect to port 80, assume Newt is working
        return 0
    else
        echo "Cannot connect to app service via Newt"
        return 1
    fi
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