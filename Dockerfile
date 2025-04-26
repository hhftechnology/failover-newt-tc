# Dockerfile for Newt-Tailscale Failover Gateway
FROM hhftechnology/alpine:3.21

# Build arguments
ARG TAILSCALE_VERSION=1.80.3
ARG NEWT_VERSION=1.1.0
ARG TARGETARCH

# Install base packages
RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    iptables \
    iproute2 \
    supervisor \
    linux-headers \
    build-base \
    kmod \
    jq \
    netcat-openbsd \
    procps \
    wget \
    nodejs \
    npm \
    sqlite-dev

# Install Node.js packages for monitoring dashboard
RUN npm install -g express express-ws ws

# Install Tailscale
RUN curl -sL "https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_${TARGETARCH}.tgz" \
    | tar -zxf - -C /usr/local/bin --strip=1 \
    tailscale_${TAILSCALE_VERSION}_${TARGETARCH}/tailscaled \
    tailscale_${TAILSCALE_VERSION}_${TARGETARCH}/tailscale

# Install Newt
RUN ARCH=$([ "${TARGETARCH}" = "amd64" ] && echo "amd64" || echo "arm64") && \
    curl -sL "https://github.com/fosrl/newt/releases/download/${NEWT_VERSION}/newt_linux_${ARCH}" \
    -o /usr/local/bin/newt && \
    chmod +x /usr/local/bin/newt

# Install monitoring dashboard dependencies
RUN npm install -g express express-ws ws

# Create necessary directories
RUN mkdir -p \
    /var/run/tailscale \
    /var/lib/tailscale \
    /var/log/supervisor \
    /opt/failover-gateway \
    /opt/failover-gateway/public \
    /opt/failover-gateway/logs

# Copy configuration and scripts
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/tailscale-up.sh /usr/local/bin/tailscale-up.sh
COPY scripts/newt-up.sh /usr/local/bin/newt-up.sh
COPY scripts/failover-monitor.sh /usr/local/bin/failover-monitor.sh
COPY scripts/failover-switch.sh /usr/local/bin/failover-switch.sh
COPY scripts/health-check.sh /usr/local/bin/health-check.sh
COPY scripts/notification.sh /usr/local/bin/notification.sh
COPY web/dashboard.js /opt/failover-gateway/dashboard.js
COPY web/public/ /opt/failover-gateway/public/

# Set execute permissions for scripts
RUN chmod +x \
    /entrypoint.sh \
    /usr/local/bin/tailscale-up.sh \
    /usr/local/bin/newt-up.sh \
    /usr/local/bin/failover-monitor.sh \
    /usr/local/bin/failover-switch.sh \
    /usr/local/bin/health-check.sh \
    /usr/local/bin/notification.sh

# Set environment variables
ENV NO_AUTOUPDATE=true \
    FAILOVER_MODE=immediate \
    PRIMARY_SERVICE=newt \
    HEALTH_CHECK_INTERVAL=10 \
    HEALTH_CHECK_TIMEOUT=5 \
    HEALTH_CHECK_FAILURES_THRESHOLD=3 \
    HEALTH_CHECK_RECOVERY_THRESHOLD=5 \
    ENABLE_NOTIFICATIONS=false

EXPOSE 9090

ENTRYPOINT ["/entrypoint.sh"]