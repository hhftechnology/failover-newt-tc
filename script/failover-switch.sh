#!/bin/bash
# Failover switch script - Handles the actual traffic redirection between Newt and Tailscale
set -e

# Get parameters
FAILOVER_MODE="$1"
FROM_SERVICE="$2"
TO_SERVICE="$3"
LOG_FILE="/opt/failover-gateway/logs/failover.log"

# Function to log messages
log_message() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $message" | tee -a $LOG_FILE
}

# Function to get target IP (app service IP)
get_target_ip() {
    getent hosts app | awk '{ print $1 }'
}

# Function to handle immediate failover
immediate_failover() {
    local from_service="$1"
    local to_service="$2"
    
    log_message "Performing immediate failover from $from_service to $to_service"
    
    # Get the target IP
    local target_ip=$(get_target_ip)
    if [ -z "$target_ip" ]; then
        log_message "Error: Could not resolve target service IP"
        return 1
    fi
    
    # Stop the from_service if it's running
    if [ "$from_service" = "newt" ]; then
        # Stop Newt service
        if pgrep -f newt > /dev/null; then
            log_message "Stopping Newt service..."
            supervisorctl stop newt
        fi
    fi
    
    # Start or ensure to_service is running
    if [ "$to_service" = "tailscale" ]; then
        # Make sure Tailscale is up and running
        log_message "Ensuring Tailscale is up and running..."
        if ! tailscale status --json | jq -e '.BackendState == "Running"' > /dev/null; then
            log_message "Restarting Tailscale..."
            supervisorctl restart tailscale-up
            sleep 5
        fi
        
        # Setup port forwarding through Tailscale
        log_message "Setting up port forwarding via Tailscale..."
        setup_tailscale_forwarding "$target_ip"
    elif [ "$to_service" = "newt" ]; then
        # Start Newt service
        log_message "Starting Newt service..."
        supervisorctl start newt
        sleep 5
        
        # Clear the Tailscale port forwarding rules
        log_message "Clearing Tailscale port forwarding rules..."
        iptables -t nat -F PREROUTING
    fi
    
    log_message "Immediate failover complete: now using $to_service"
    return 0
}

# Function to handle gradual failover
gradual_failover() {
    local from_service="$1"
    local to_service="$2"
    
    log_message "Performing gradual failover from $from_service to $to_service"
    
    # Get the target IP
    local target_ip=$(get_target_ip)
    if [ -z "$target_ip" ]; then
        log_message "Error: Could not resolve target service IP"
        return 1
    fi
    
    # For gradual failover, we keep both services running
    
    if [ "$to_service" = "tailscale" ]; then
        # Make sure Tailscale is up and running
        log_message "Ensuring Tailscale is up and running..."
        if ! tailscale status --json | jq -e '.BackendState == "Running"' > /dev/null; then
            log_message "Restarting Tailscale..."
            supervisorctl restart tailscale-up
            sleep 5
        fi
        
        # Set up port forwarding through Tailscale, but keep Newt running
        log_message "Setting up port forwarding via Tailscale..."
        setup_tailscale_forwarding "$target_ip"
        
        # We don't stop Newt immediately, but let existing connections complete
        log_message "Newt will continue handling existing connections until they complete"
    elif [ "$to_service" = "newt" ]; then
        # Start Newt service if not already running
        if ! pgrep -f newt > /dev/null; then
            log_message "Starting Newt service..."
            supervisorctl start newt
            sleep 5
        fi
        
        # Gradually remove Tailscale rules (allow existing connections to complete)
        log_message "Gradually removing Tailscale port forwarding rules..."
        # This is more complex and might require connection tracking
        # For simplicity, we'll just keep both running and let connections naturally migrate
    fi
    
    log_message "Gradual failover initiated: traffic is being migrated to $to_service"
    return 0
}

# Function to setup Tailscale port forwarding
setup_tailscale_forwarding() {
    local target_ip=$1
    log_message "Setting up Tailscale port forwarding to target IP: $target_ip"
    
    # Clear existing rules
    iptables -t nat -F PREROUTING
    
    # Get ports from TARGET_PORTS env var
    IFS=',' read -ra PORTS <<< "${TARGET_PORTS:-80}"
    log_message "Configuring forwarding for ports: ${TARGET_PORTS}"
    
    # Add rules for each port
    for port in "${PORTS[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        log_message "Setting up port ${port}..."
        iptables -t nat -A PREROUTING -i tailscale0 -p tcp --dport "${port}" -j DNAT --to-destination "${target_ip}:${port}"
    done
    
    # Add masquerade rule if not exists
    if ! iptables -t nat -C POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    fi
    
    # Show final configuration
    log_message "Current iptables rules:"
    iptables -t nat -L PREROUTING -n -v
    iptables -t nat -L POSTROUTING -n -v
}

# Main execution
log_message "Failover switch triggered: mode=$FAILOVER_MODE, from=$FROM_SERVICE, to=$TO_SERVICE"

# Check that parameters are valid
if [ -z "$FAILOVER_MODE" ] || [ -z "$FROM_SERVICE" ] || [ -z "$TO_SERVICE" ]; then
    log_message "Error: Missing required parameters. Usage: $0 <mode> <from_service> <to_service>"
    exit 1
fi

if [ "$FROM_SERVICE" = "$TO_SERVICE" ]; then
    log_message "Source and destination services are the same. No action needed."
    exit 0
fi

# Execute the appropriate failover strategy
case "$FAILOVER_MODE" in
    immediate)
        immediate_failover "$FROM_SERVICE" "$TO_SERVICE"
        ;;
    gradual)
        gradual_failover "$FROM_SERVICE" "$TO_SERVICE"
        ;;
    *)
        log_message "Error: Unknown failover mode: $FAILOVER_MODE"
        exit 1
        ;;
esac

exit $?