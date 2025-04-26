#!/bin/bash
# Bootstrap script to handle container initialization and dependency checks
set -e

DASHBOARD_DIR="/opt/failover-gateway"
LOG_FILE="${DASHBOARD_DIR}/logs/bootstrap.log"

# Function to log messages
log_message() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $message" | tee -a $LOG_FILE
}

# Create necessary directories
mkdir -p ${DASHBOARD_DIR}/logs
mkdir -p ${DASHBOARD_DIR}/public
touch $LOG_FILE

log_message "Starting container bootstrap process"

# Check and install Node.js dependencies
log_message "Checking Node.js dependencies"
if ! npm list --prefix ${DASHBOARD_DIR} express >/dev/null 2>&1; then
    log_message "Express not found, installing dependencies"
    cd ${DASHBOARD_DIR}
    npm install express express-ws ws
    log_message "Node.js dependencies installed"
else
    log_message "Node.js dependencies already installed"
fi

# Set up TUN device
log_message "Setting up TUN device"
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
    if [ -e /dev/net/tun ]; then
        log_message "Removing existing non-character device /dev/net/tun"
        rm -f /dev/net/tun
    fi
    log_message "Creating TUN device"
    mknod /dev/net/tun c 10 200
    chmod 0666 /dev/net/tun
fi

# Verify TUN device
if [ -c /dev/net/tun ]; then
    log_message "TUN device exists and is a character device"
else
    log_message "ERROR: TUN device setup failed"
fi

# Check TUN module
log_message "Checking for TUN module"
if lsmod | grep -q "^tun "; then
    log_message "TUN module is loaded"
else
    log_message "Attempting to load TUN module"
    modprobe tun 2>/dev/null || log_message "Failed to load TUN module - container may need privileged mode"
fi

# Verify iptables access
log_message "Checking iptables access"
if iptables -L -n &>/dev/null; then
    log_message "Container has iptables access"
else
    log_message "WARNING: Container does not have proper iptables access - container needs NET_ADMIN capability"
fi

# Setup network configuration
log_message "Setting up basic network configuration"
if [ -n "${TARGET_PORTS}" ]; then
    log_message "Target ports for forwarding: ${TARGET_PORTS}"
fi

# Fix permissions on directories
log_message "Setting correct permissions"
chmod -R 755 ${DASHBOARD_DIR}/public

# Create a placeholder status file if it doesn't exist
if [ ! -f "${DASHBOARD_DIR}/status.json" ]; then
    log_message "Creating initial status file"
    echo "{\"active_service\":\"${PRIMARY_SERVICE}\",\"primary_service\":\"${PRIMARY_SERVICE}\",\"failover_active\":false,\"last_failover\":null,\"health\":{\"newt\":\"unknown\",\"tailscale\":\"unknown\"}}" > "${DASHBOARD_DIR}/status.json"
fi

# Check for web dashboard files
if [ ! -f "${DASHBOARD_DIR}/public/index.html" ]; then
    log_message "WARNING: Dashboard HTML file missing"
fi

if [ ! -f "${DASHBOARD_DIR}/public/dashboard.js" ]; then
    log_message "WARNING: Client dashboard.js file missing"
    
    # Create the file with a placeholder if missing
    echo "// Dashboard client script will be installed here" > "${DASHBOARD_DIR}/public/dashboard.js"
fi

if [ ! -f "${DASHBOARD_DIR}/dashboard-server.js" ]; then
    log_message "WARNING: Server dashboard-server.js file missing"
fi

log_message "Bootstrap complete"
exit 0