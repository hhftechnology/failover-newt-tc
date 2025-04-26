# Newt-Tailscale Failover Gateway

This project provides an automatic failover solution between Newt and Tailscale. If the Newt tunnel fails, traffic is automatically redirected to Tailscale without interruption.

<img src="images/image.png" alt="Preview"/>

## Features

- **Automatic Failover**: Seamlessly switches to Tailscale when Newt becomes unavailable
- **Self-healing**: Automatically returns to Newt when service is restored
- **Configurable Health Checks**: Customize monitoring parameters
- **Zero Downtime Switching**: Maintains connections during failover
- **Comprehensive Logging**: Track all failover events and health status
- **Multiple Failover Modes**: Choose between immediate or gradual failover

## How It Works

1. The system continuously monitors the health of the Newt tunnel connection
2. When a failure is detected (based on configurable thresholds), the failover mechanism is triggered
3. Traffic is automatically redirected through Tailscale while Newt is unavailable
4. Once Newt service is restored, traffic can either be immediately switched back or gradually migrated

### Important: Route Advertisement Configuration

For seamless failover, Tailscale must be configured to advertise routes to the same private network that Newt connects to. This ensures that when traffic switches from Newt to Tailscale, it can still reach the same internal services.

1. Identify the private IP range(s) that your services use (e.g., 192.168.1.0/24)
2. Configure Tailscale to advertise these routes using the `TAILSCALE_ADVERTISE_ROUTES` parameter
3. Ensure that your Tailscale account has subnet routing enabled (may require a business plan)
4. Approve the route advertisement in the Tailscale admin console after first deployment

Without proper route advertisement, failover may appear to work but traffic won't reach your internal services.

## Prerequisites

- Docker and Docker Compose
- Tailscale account with an auth key
- Pangolin deployment with Newt credentials
- Basic understanding of networking concepts

## Environment Variables

```env
# Core Configuration
ENABLE_FAILOVER=true
FAILOVER_MODE=immediate  # immediate or gradual
PRIMARY_SERVICE=newt     # newt or tailscale (which one is primary)

# Health Check Configuration
HEALTH_CHECK_INTERVAL=10        # seconds between checks
HEALTH_CHECK_TIMEOUT=5          # seconds before a check times out
HEALTH_CHECK_FAILURES_THRESHOLD=3  # failures before triggering failover
HEALTH_CHECK_RECOVERY_THRESHOLD=5  # successes before switching back

# Newt Configuration
NEWT_ID=your-newt-id
NEWT_SECRET=your-newt-secret
PANGOLIN_ENDPOINT=https://your-pangolin-server.com

# Tailscale Configuration
TAILSCALE_AUTH_KEY=tskey-auth-xxxxx-xxxxxxxxxxxxx
TAILSCALE_HOSTNAME=failover-gateway
TARGET_PORTS=80,443,3000,8080  # Ports to forward via Tailscale

# *** IMPORTANT: Configure route advertisement for proper failover ***
# Advertise the same private subnets that Newt is connecting to
TAILSCALE_ADVERTISE_ROUTES=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16  # Customize to match your network

# Optional Tailscale Settings
TAILSCALE_ACCEPT_DNS=true
TAILSCALE_ACCEPT_ROUTES=false
TAILSCALE_ADVERTISE_EXIT_NODE=false
TAILSCALE_SSH=false

# Notification Settings (optional)
ENABLE_NOTIFICATIONS=false
NOTIFICATION_WEBHOOK=https://your-webhook-url.com
```

## Usage Examples

### Basic Failover Setup

```yaml
version: '3'
services:
  failover-gateway:
    image: hhftechnology/failover-newt-tc:latest:latest
    cap_add:
      - NET_ADMIN
    environment:
      - ENABLE_FAILOVER=true
      - FAILOVER_MODE=immediate
      - PRIMARY_SERVICE=newt
      - HEALTH_CHECK_INTERVAL=10
      - HEALTH_CHECK_FAILURES_THRESHOLD=3
      - NEWT_ID=your-newt-id
      - NEWT_SECRET=your-newt-secret
      - PANGOLIN_ENDPOINT=https://your-pangolin-server.com
      - TAILSCALE_AUTH_KEY=tskey-auth-xxxxx-xxxxxxxxxxxxx
      - TAILSCALE_HOSTNAME=failover-gateway
      - TARGET_PORTS=80,3000
      # CRITICAL: Configure Tailscale to advertise the network your services are on
      - TAILSCALE_ADVERTISE_ROUTES=192.168.1.0/24
    volumes:
      - ./data/tailscale:/var/lib/tailscale
    devices:
      - /dev/net/tun:/dev/net/tun
    restart: unless-stopped

  webapp:
    image: nginx:alpine
    expose:
      - "80"
    restart: unless-stopped
    # The internal IP range must match what's configured in TAILSCALE_ADVERTISE_ROUTES
    networks:
      - frontend

networks:
  frontend:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.1.0/24  # This subnet must be advertised in Tailscale
```

### Gradual Failover with Notifications

```yaml
version: '3'
services:
  failover-gateway:
    image: hhftechnology/failover-newt-tc:latest:latest
    cap_add:
      - NET_ADMIN
    environment:
      - ENABLE_FAILOVER=true
      - FAILOVER_MODE=gradual
      - PRIMARY_SERVICE=newt
      - HEALTH_CHECK_INTERVAL=5
      - HEALTH_CHECK_FAILURES_THRESHOLD=5
      - HEALTH_CHECK_RECOVERY_THRESHOLD=10
      - NEWT_ID=your-newt-id
      - NEWT_SECRET=your-newt-secret
      - PANGOLIN_ENDPOINT=https://your-pangolin-server.com
      - TAILSCALE_AUTH_KEY=tskey-auth-xxxxx-xxxxxxxxxxxxx
      - TAILSCALE_HOSTNAME=failover-gateway
      - TARGET_PORTS=80,443,8080
      - ENABLE_NOTIFICATIONS=true
      - NOTIFICATION_WEBHOOK=https://your-webhook-url.com
    volumes:
      - ./data/tailscale:/var/lib/tailscale
    devices:
      - /dev/net/tun:/dev/net/tun
    restart: unless-stopped

  api:
    image: node:alpine
    expose:
      - "80"
    restart: unless-stopped
```

## Architecture

The failover gateway follows this architecture:

1. **Health Monitor**: Continuously checks the Newt tunnel's health
2. **Failover Controller**: Manages switching between Newt and Tailscale
3. **Connection Manager**: Maintains and routes active connections
4. **Notification System**: Alerts administrators of failover events
5. **Statistics Collector**: Tracks performance metrics and failover history

## Monitoring Dashboard

A simple monitoring dashboard is available at `http://[gateway-ip]:9090/status` showing:

- Current active service (Newt or Tailscale)
- Health status of both services
- Failover history
- Connection statistics
- System resource usage

## Failover Modes

### Immediate Failover

All traffic is instantly redirected to the backup service when a failure is detected. This minimizes downtime but may cause some active connections to drop.

### Gradual Failover

New connections are routed through the backup service, while existing connections continue through the primary service until they naturally terminate. This prevents connection disruption but may take longer to complete the failover.

## Customizing Health Checks

The health monitoring system can be configured to check various aspects:

- Connection status
- Latency thresholds
- Packet loss rates
- Bandwidth availability
- External endpoint accessibility

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - See LICENSE file for details