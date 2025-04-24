#!/bin/bash
set -e

# Wait for tailscaled to start
sleep 5

# Check if auth key is provided
if [ -z "${TAILSCALE_AUTH_KEY}" ]; then
    echo "Error: TAILSCALE_AUTH_KEY is not set"
    exit 1
fi

# Setup port forwarding
setup_port_forwarding() {
    local target_ip=$1
    echo "Starting port forwarding setup..."
    echo "Target IP: ${target_ip}"

    # Clear existing rules
    iptables -t nat -F PREROUTING

    # Get ports from TARGET_PORTS env var
    IFS=',' read -ra PORTS <<< "${TARGET_PORTS:-3000}"
    echo "Configuring forwarding for ports: ${TARGET_PORTS}"

    # Add rules for each port
    for port in "${PORTS[@]}"; do
        port=$(echo "$port" | tr -d ' ')
        echo "Setting up port ${port}..."
        iptables -t nat -A PREROUTING -i tailscale0 -p tcp --dport "${port}" -j DNAT --to-destination "${target_ip}:${port}"
    done

    # Add masquerade rule if not exists
    if ! iptables -t nat -C POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    fi

    # Show final configuration
    echo "Current iptables rules:"
    iptables -t nat -L PREROUTING -n -v
    iptables -t nat -L POSTROUTING -n -v
}

echo "Starting Tailscale authentication..."
TAILSCALE_UP_FLAGS=(
    --auth-key="${TAILSCALE_AUTH_KEY}"
    --hostname="${TAILSCALE_HOSTNAME:-$(hostname)}"
    --accept-dns=${TAILSCALE_ACCEPT_DNS:-true}
    --accept-routes=${TAILSCALE_ACCEPT_ROUTES:-false}
    --advertise-exit-node=${TAILSCALE_ADVERTISE_EXIT_NODE:-false}
    --ssh=${TAILSCALE_SSH:-false}
)

# Add advertise-routes if specified
if [ -n "${TAILSCALE_ADVERTISE_ROUTES}" ]; then
    TAILSCALE_UP_FLAGS+=(--advertise-routes="${TAILSCALE_ADVERTISE_ROUTES}")
fi

# Try to authenticate with retries
MAX_RETRIES=3
for ((i=1; i<=MAX_RETRIES; i++)); do
    echo "Authentication attempt $i of $MAX_RETRIES..."
    
    if tailscale up "${TAILSCALE_UP_FLAGS[@]}" 2>&1; then
        echo "Tailscale authentication successful!"
        
        # Wait for connection to be fully established
        for ((j=1; j<=10; j++)); do
            if tailscale status 2>/dev/null | grep -q "^100\."; then
                echo "Tailscale connection confirmed!"
                
                # Setup port forwarding
                target_ip=$(getent hosts app | awk '{ print $1 }')
                if [ -n "${target_ip}" ]; then
                    setup_port_forwarding "${target_ip}"
                    exit 0
                else
                    echo "Warning: Could not resolve target service IP"
                    exit 1
                fi
            fi
            echo "Waiting for connection to establish... ($j/10)"
            sleep 2
        done
    fi
    
    echo "Retrying in 5 seconds..."
    sleep 5
done

echo "Failed to authenticate after $MAX_RETRIES attempts"
exit 1