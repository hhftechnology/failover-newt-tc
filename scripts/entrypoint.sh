#!/bin/bash
set -e

# Setup TUN device
mkdir -p /dev/net
if [ ! -e /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
    chmod 600 /dev/net/tun
fi

# Create necessary directories
mkdir -p /var/run/tailscale
mkdir -p /var/lib/tailscale
mkdir -p /opt/failover-gateway/logs
mkdir -p /opt/failover-gateway/public

# Setup initial status file
echo "{\"active_service\":\"${PRIMARY_SERVICE:-newt}\",\"primary_service\":\"${PRIMARY_SERVICE:-newt}\",\"failover_active\":false,\"last_failover\":null,\"health\":{\"newt\":\"unknown\",\"tailscale\":\"unknown\"}}" > /opt/failover-gateway/status.json

# Log startup information
echo "[$(date +%Y-%m-%d\ %H:%M:%S)] Failover Gateway starting up" > /opt/failover-gateway/logs/failover.log
echo "[$(date +%Y-%m-%d\ %H:%M:%S)] Primary service: ${PRIMARY_SERVICE:-newt}" >> /opt/failover-gateway/logs/failover.log
echo "[$(date +%Y-%m-%d\ %H:%M:%S)] Failover mode: ${FAILOVER_MODE:-immediate}" >> /opt/failover-gateway/logs/failover.log

# Set default values for environment variables
export ENABLE_FAILOVER=${ENABLE_FAILOVER:-true}
export FAILOVER_MODE=${FAILOVER_MODE:-immediate}
export PRIMARY_SERVICE=${PRIMARY_SERVICE:-newt}
export HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-10}
export HEALTH_CHECK_TIMEOUT=${HEALTH_CHECK_TIMEOUT:-5}
export HEALTH_CHECK_FAILURES_THRESHOLD=${HEALTH_CHECK_FAILURES_THRESHOLD:-3}
export HEALTH_CHECK_RECOVERY_THRESHOLD=${HEALTH_CHECK_RECOVERY_THRESHOLD:-5}
export ENABLE_NOTIFICATIONS=${ENABLE_NOTIFICATIONS:-false}

# Start supervisord
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf