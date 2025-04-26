// Server-side Dashboard Implementation
const express = require('express');
const expressWs = require('express-ws');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

// Create Express app
const app = express();
const port = 9090;

// Initialize WebSocket support
expressWs(app);

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
    },
    notifications: []
};

// Connected WebSocket clients
const clients = [];

// Function to read status file
function readStatusFile() {
    try {
        const statusFile = path.join(__dirname, 'status.json');
        if (fs.existsSync(statusFile)) {
            const data = fs.readFileSync(statusFile, 'utf8');
            try {
                statusData = JSON.parse(data);
                return true;
            } catch (parseError) {
                console.error('Error parsing status file:', parseError);
                return false;
            }
        }
        return false;
    } catch (error) {
        console.error('Error reading status file:', error);
        return false;
    }
}

// Function to read log file
function readLogFile(maxLines = 100) {
    try {
        const logFile = path.join(__dirname, 'logs', 'failover.log');
        if (fs.existsSync(logFile)) {
            const data = fs.readFileSync(logFile, 'utf8');
            return data.split('\n')
                .filter(line => line.trim() !== '')
                .slice(-maxLines);
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
        uptime: '0',
        network: {
            in: '0 KB/s',
            out: '0 KB/s'
        }
    };
    
    // Get CPU usage
    exec("top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\\([0-9.]*\\)%* id.*/\\1/' | awk '{print 100 - $1\"%\"}'", (err, stdout) => {
        if (!err) {
            systemInfo.cpu = stdout.trim();
        }
        
        // Get memory usage
        exec("free -m | grep Mem | awk '{print $3, $2}'", (err, stdout) => {
            if (!err) {
                const [used, total] = stdout.trim().split(' ');
                const percentage = Math.round((used / total) * 100);
                systemInfo.memory = {
                    percentage: `${percentage}%`,
                    used: `${used}MB`,
                    total: `${total}MB`
                };
            }
            
            // Get uptime
            exec("cat /proc/uptime | awk '{print $1}'", (err, stdout) => {
                if (!err) {
                    systemInfo.uptime = stdout.trim();
                }
                
                // Get network stats (optional)
                exec("cat /proc/net/dev | grep eth0 | awk '{print $2, $10}'", (err, stdout) => {
                    if (!err && stdout.trim()) {
                        const [bytesIn, bytesOut] = stdout.trim().split(' ');
                        systemInfo.network = {
                            in: `${Math.round(bytesIn / 1024)} KB`,
                            out: `${Math.round(bytesOut / 1024)} KB`
                        };
                    }
                    
                    callback(systemInfo);
                });
            });
        });
    });
}

// Function to check service status
function checkServicesStatus(callback) {
    // Check Newt status
    exec("pgrep -f newt", (errNewt, stdoutNewt) => {
        const newtRunning = !errNewt && stdoutNewt.trim() !== '';
        
        // Check Tailscale status
        exec("pgrep -f tailscaled", (errTail, stdoutTail) => {
            const tailscaleRunning = !errTail && stdoutTail.trim() !== '';
            
            callback({
                newt: newtRunning ? 'running' : 'stopped',
                tailscale: tailscaleRunning ? 'running' : 'stopped'
            });
        });
    });
}

// Function to broadcast to all connected clients
function broadcast(type, data) {
    const message = JSON.stringify({ type, data });
    clients.forEach(client => {
        if (client.readyState === 1) { // 1 = WebSocket.OPEN
            client.send(message);
        }
    });
}

// Setup file watching for status updates
let lastStatusCheckTime = 0;
let lastStatusData = JSON.stringify(statusData);

function checkForStatusUpdates() {
    const now = Date.now();
    
    // Don't check more often than every 1 second
    if (now - lastStatusCheckTime < 1000) {
        return;
    }
    
    lastStatusCheckTime = now;
    
    if (readStatusFile()) {
        const currentStatusData = JSON.stringify(statusData);
        
        // Only broadcast if status has changed
        if (currentStatusData !== lastStatusData) {
            broadcast('status', statusData);
            lastStatusData = currentStatusData;
        }
    }
}

// Setup file watching for log updates
let lastLogLength = 0;

function checkForLogUpdates() {
    const logs = readLogFile();
    
    if (logs.length > lastLogLength) {
        const newLogs = logs.slice(lastLogLength);
        newLogs.forEach(log => {
            broadcast('log', log);
        });
        lastLogLength = logs.length;
    }
}

// API endpoints
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.get('/api/status', (req, res) => {
    readStatusFile();
    res.json(statusData);
});

app.get('/api/logs', (req, res) => {
    const maxLines = req.query.max ? parseInt(req.query.max) : 100;
    const logs = readLogFile(maxLines);
    res.json({ logs });
});

app.get('/api/system', (req, res) => {
    getSystemInfo(info => {
        res.json(info);
    });
});

app.get('/api/services', (req, res) => {
    checkServicesStatus(status => {
        res.json(status);
    });
});

// WebSocket endpoint for live updates
app.ws('/api/live', (ws, req) => {
    console.log('WebSocket client connected');
    clients.push(ws);
    
    // Send initial data
    readStatusFile();
    ws.send(JSON.stringify({ type: 'status', data: statusData }));
    
    // Send initial logs
    const logs = readLogFile();
    ws.send(JSON.stringify({ type: 'logs', data: logs }));
    lastLogLength = logs.length;
    
    // Get system info
    getSystemInfo(info => {
        ws.send(JSON.stringify({ type: 'system', data: info }));
    });
    
    // Get services status
    checkServicesStatus(status => {
        ws.send(JSON.stringify({ type: 'services', data: status }));
    });
    
    // Clean up on connection close
    ws.on('close', () => {
        console.log('WebSocket client disconnected');
        const index = clients.indexOf(ws);
        if (index !== -1) {
            clients.splice(index, 1);
        }
    });
});

// Setup intervals for updates
setInterval(() => {
    checkForStatusUpdates();
    checkForLogUpdates();
}, 1000);

setInterval(() => {
    getSystemInfo(info => {
        broadcast('system', info);
    });
}, 5000);

setInterval(() => {
    checkServicesStatus(status => {
        broadcast('services', status);
    });
}, 5000);

// Start the server
app.listen(port, () => {
    console.log(`Dashboard server running on port ${port}`);
    
    // Create logs directory if it doesn't exist
    const logsDir = path.join(__dirname, 'logs');
    if (!fs.existsSync(logsDir)) {
        fs.mkdirSync(logsDir, { recursive: true });
    }
    
    // Write startup message to log
    const startupMessage = `[${new Date().toISOString()}] Dashboard server started`;
    console.log(startupMessage);
    
    // Initialize log file if it doesn't exist
    const logFile = path.join(logsDir, 'failover.log');
    if (!fs.existsSync(logFile)) {
        fs.writeFileSync(logFile, startupMessage + '\n');
    }
});

// Error handling
process.on('uncaughtException', (err) => {
    console.error('Uncaught exception:', err);
});

process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});