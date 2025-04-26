#!/bin/bash
set -e

echo "Starting Failover Gateway..."

# Run bootstrap script to ensure everything is properly configured
/usr/local/bin/bootstrap.sh

# Create necessary directories
mkdir -p /var/run/tailscale
mkdir -p /var/lib/tailscale
mkdir -p /opt/failover-gateway/logs
mkdir -p /opt/failover-gateway/public

# Setup initial status file if it doesn't exist
if [ ! -f "/opt/failover-gateway/status.json" ]; then
    echo "{\"active_service\":\"${PRIMARY_SERVICE:-newt}\",\"primary_service\":\"${PRIMARY_SERVICE:-newt}\",\"failover_active\":false,\"last_failover\":null,\"health\":{\"newt\":\"unknown\",\"tailscale\":\"unknown\"}}" > /opt/failover-gateway/status.json
fi

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

# Make sure client dashboard file exists
if [ ! -f "/opt/failover-gateway/public/dashboard.js" ]; then
    echo "Client-side dashboard.js not found, creating it"
    cat > /opt/failover-gateway/public/dashboard.js << 'EOL'
// Client-side Dashboard JavaScript
document.addEventListener('DOMContentLoaded', function() {
    // DOM Elements
    const activeServiceElement = document.getElementById('active-service-status');
    const primaryServiceElement = document.getElementById('primary-service');
    const failoverActiveElement = document.getElementById('failover-active');
    const lastFailoverElement = document.getElementById('last-failover');
    const newtHealthElement = document.getElementById('newt-health');
    const tailscaleHealthElement = document.getElementById('tailscale-health');
    const logEntriesElement = document.getElementById('log-entries');
    const cpuUsageElement = document.getElementById('cpu-usage');
    const memoryUsageElement = document.getElementById('memory-usage');
    const uptimeElement = document.getElementById('uptime');

    // Initialize WebSocket connection
    function initWebSocket() {
        const ws = new WebSocket(`ws://${window.location.host}/api/live`);
        
        ws.onopen = function() {
            console.log('WebSocket connection established');
            appendLogEntry('Dashboard connected to live updates');
        };
        
        ws.onmessage = function(event) {
            const message = JSON.parse(event.data);
            
            switch(message.type) {
                case 'status':
                    updateStatusDisplay(message.data);
                    break;
                case 'log':
                    appendLogEntry(message.data);
                    break;
                case 'system':
                    updateSystemInfo(message.data);
                    break;
            }
        };
        
        ws.onclose = function() {
            console.log('WebSocket connection closed');
            appendLogEntry('Dashboard disconnected from live updates. Reconnecting in 5 seconds...');
            setTimeout(initWebSocket, 5000);
        };
        
        return ws;
    }
    
    // Function to update the status display
    function updateStatusDisplay(status) {
        if (!status) return;
        
        // Update active service
        if (activeServiceElement) {
            activeServiceElement.textContent = status.active_service ? 
                (status.active_service.charAt(0).toUpperCase() + status.active_service.slice(1)) : 'Unknown';
            activeServiceElement.className = 'status-indicator status-up';
        }
        
        // Update service details
        if (primaryServiceElement) {
            primaryServiceElement.textContent = status.primary_service ? 
                (status.primary_service.charAt(0).toUpperCase() + status.primary_service.slice(1)) : 'Unknown';
        }
        
        if (failoverActiveElement) {
            failoverActiveElement.textContent = status.failover_active ? 'Yes' : 'No';
        }
        
        if (lastFailoverElement && status.last_failover) {
            lastFailoverElement.textContent = status.last_failover;
        }
        
        // Update health statuses
        if (newtHealthElement && status.health && status.health.newt) {
            updateHealthStatus(newtHealthElement, status.health.newt);
        }
        
        if (tailscaleHealthElement && status.health && status.health.tailscale) {
            updateHealthStatus(tailscaleHealthElement, status.health.tailscale);
        }
    }
    
    // Function to update health status indicators
    function updateHealthStatus(element, status) {
        element.textContent = status.charAt(0).toUpperCase() + status.slice(1);
        
        switch(status) {
            case 'up':
                element.className = 'health-status status-up';
                break;
            case 'down':
                element.className = 'health-status status-down';
                break;
            case 'standby':
                element.className = 'health-status status-standby';
                break;
            default:
                element.className = 'health-status status-unknown';
        }
    }
    
    // Function to update system info
    function updateSystemInfo(info) {
        if (cpuUsageElement) cpuUsageElement.textContent = info.cpu || '0%';
        if (memoryUsageElement) {
            memoryUsageElement.textContent = info.memory ? 
                `${info.memory.percentage} (${info.memory.used} / ${info.memory.total})` : 
                'Loading...';
        }
        if (uptimeElement) uptimeElement.textContent = formatUptime(info.uptime || '0');
    }
    
    // Function to format uptime string
    function formatUptime(uptime) {
        const uptimeSeconds = parseInt(uptime.split(' ')[0]);
        
        const days = Math.floor(uptimeSeconds / 86400);
        const hours = Math.floor((uptimeSeconds % 86400) / 3600);
        const minutes = Math.floor((uptimeSeconds % 3600) / 60);
        const seconds = uptimeSeconds % 60;
        
        let result = '';
        if (days > 0) result += `${days}d `;
        if (hours > 0 || days > 0) result += `${hours}h `;
        if (minutes > 0 || hours > 0 || days > 0) result += `${minutes}m `;
        result += `${seconds}s`;
        
        return result;
    }
    
    // Function to append log entry
    function appendLogEntry(entry) {
        if (!logEntriesElement || !entry) return;
        
        const logEntry = document.createElement('div');
        logEntry.textContent = entry;
        logEntriesElement.appendChild(logEntry);
        
        // Auto-scroll to bottom
        logEntriesElement.scrollTop = logEntriesElement.scrollHeight;
        
        // Limit to 100 entries
        while (logEntriesElement.children.length > 100) {
            logEntriesElement.removeChild(logEntriesElement.firstChild);
        }
    }
    
    // Function to fetch initial data
    async function fetchInitialData() {
        try {
            // Fetch status
            const statusResponse = await fetch('/api/status');
            if (statusResponse.ok) {
                const statusData = await statusResponse.json();
                updateStatusDisplay(statusData);
            }
            
            // Fetch logs
            const logsResponse = await fetch('/api/logs');
            if (logsResponse.ok) {
                const logsData = await logsResponse.json();
                if (logsData.logs) {
                    logsData.logs.forEach(log => appendLogEntry(log));
                }
            }
            
            // Fetch system info
            const systemResponse = await fetch('/api/system');
            if (systemResponse.ok) {
                const systemData = await systemResponse.json();
                updateSystemInfo(systemData);
            }
        } catch (error) {
            console.error('Error fetching initial data:', error);
            appendLogEntry('Error fetching initial data. Will retry with live updates.');
        }
    }
    
    // Initialize the dashboard
    fetchInitialData();
    const socket = initWebSocket();
    
    // Set up refresh function
    function refreshData() {
        fetchInitialData();
    }
    
    // Add refresh button functionality if present
    const refreshButton = document.getElementById('refresh-button');
    if (refreshButton) {
        refreshButton.addEventListener('click', refreshData);
    }
    
    // Set automatic refresh as fallback
    setInterval(refreshData, 30000);
});
EOL
fi

# Make sure server-side dashboard script exists
if [ ! -f "/opt/failover-gateway/dashboard-server.js" ]; then
    echo "Server-side dashboard-server.js not found, creating it"
    cat > /opt/failover-gateway/dashboard-server.js << 'EOL'
// Simple server-side Dashboard Implementation
const express = require('express');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const WebSocket = require('ws');

// Create Express app
const app = express();
const port = 9090;

// Create HTTP server
const server = require('http').createServer(app);

// Initialize WebSocket server
const wss = new WebSocket.Server({ server });

// Serve static files from public directory
app.use(express.static(path.join(__dirname, 'public')));

// Status data
let statusData = {
    active_service: process.env.PRIMARY_SERVICE || 'newt',
    primary_service: process.env.PRIMARY_SERVICE || 'newt',
    failover_active: false,
    last_failover: null,
    health: {
        newt: 'unknown',
        tailscale: 'unknown'
    }
};

// Function to read status file
function readStatusFile() {
    try {
        const statusFile = path.join(__dirname, 'status.json');
        if (fs.existsSync(statusFile)) {
            const data = fs.readFileSync(statusFile, 'utf8');
            statusData = JSON.parse(data);
        }
    } catch (error) {
        console.error('Error reading status file:', error);
    }
}

// Function to read log file
function readLogFile() {
    try {
        const logFile = path.join(__dirname, 'logs', 'failover.log');
        if (fs.existsSync(logFile)) {
            const data = fs.readFileSync(logFile, 'utf8');
            return data.split('\n').filter(line => line.trim() !== '').slice(-100);
        }
        return [];
    } catch (error) {
        console.error('Error reading log file:', error);
        return [];
    }
}

// Function to get system info
function getSystemInfo(callback) {
    const systemInfo = {
        cpu: '0%',
        memory: {
            percentage: '0%',
            used: '0MB',
            total: '0MB'
        },
        uptime: '0'
    };
    
    callback(systemInfo);
}

// API endpoints
app.get('/api/status', (req, res) => {
    readStatusFile();
    res.json(statusData);
});

app.get('/api/logs', (req, res) => {
    const logs = readLogFile();
    res.json({ logs });
});

app.get('/api/system', (req, res) => {
    getSystemInfo(info => {
        res.json(info);
    });
});

// WebSocket connections
wss.on('connection', (ws) => {
    console.log('WebSocket client connected');
    
    // Send initial data
    readStatusFile();
    ws.send(JSON.stringify({ type: 'status', data: statusData }));
    
    const logs = readLogFile();
    ws.send(JSON.stringify({ type: 'logs', data: logs }));
    
    getSystemInfo(info => {
        ws.send(JSON.stringify({ type: 'system', data: info }));
    });
    
    // Handle disconnection
    ws.on('close', () => {
        console.log('WebSocket client disconnected');
    });
});

// Start the server
server.listen(port, () => {
    console.log(`Dashboard server running on port ${port}`);
});
EOL
fi

# Make sure we have a simple HTML if it doesn't exist
if [ ! -f "/opt/failover-gateway/public/index.html" ]; then
    echo "HTML file not found, creating simple version"
    cat > /opt/failover-gateway/public/index.html << 'EOL'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Failover Gateway Status</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; }
        .container { max-width: 800px; margin: 0 auto; }
        .status-box { border: 1px solid #ddd; padding: 15px; margin-bottom: 15px; border-radius: 5px; }
        .status-up { background-color: #d4edda; color: #155724; }
        .status-down { background-color: #f8d7da; color: #721c24; }
        .status-unknown { background-color: #e2e3e5; color: #383d41; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Failover Gateway Status</h1>
        
        <div class="status-box">
            <h2>Active Service</h2>
            <p>Current: <span id="active-service-status">Loading...</span></p>
            <p>Primary: <span id="primary-service">Loading...</span></p>
            <p>Failover Active: <span id="failover-active">No</span></p>
            <p>Last Failover: <span id="last-failover">Never</span></p>
        </div>
        
        <div class="status-box">
            <h2>Health Status</h2>
            <p>Newt: <span id="newt-health" class="status-unknown">Unknown</span></p>
            <p>Tailscale: <span id="tailscale-health" class="status-unknown">Unknown</span></p>
        </div>
        
        <div class="status-box">
            <h2>System</h2>
            <p>CPU: <span id="cpu-usage">Loading...</span></p>
            <p>Memory: <span id="memory-usage">Loading...</span></p>
            <p>Uptime: <span id="uptime">Loading...</span></p>
        </div>
        
        <div class="status-box">
            <h2>Logs</h2>
            <div id="log-entries" style="height: 200px; overflow-y: auto; background: #f8f9fa; padding: 10px; font-family: monospace;"></div>
        </div>
        
        <button id="refresh-button">Refresh Data</button>
    </div>
    
    <script src="dashboard.js"></script>
</body>
</html>
EOL
fi

# Update supervisord configuration
if grep -q "dashboard.js" /etc/supervisor/conf.d/supervisord.conf; then
    echo "Updating supervisord configuration to use dashboard-server.js instead of dashboard.js"
    sed -i 's|/opt/failover-gateway/dashboard.js|/opt/failover-gateway/dashboard-server.js|g' /etc/supervisor/conf.d/supervisord.conf
fi

# Start supervisord
echo "Starting supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf