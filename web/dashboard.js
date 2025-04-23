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

    // Charts
    let availabilityChart;
    let failoverChart;
    
    // Availability data
    const availabilityData = {
        labels: Array.from({length: 20}, (_, i) => ''),
        datasets: [
            {
                label: 'Newt',
                data: Array(20).fill(null),
                borderColor: '#2ecc71',
                backgroundColor: 'rgba(46, 204, 113, 0.2)',
                tension: 0.4,
                fill: true
            },
            {
                label: 'Tailscale',
                data: Array(20).fill(null),
                borderColor: '#3498db',
                backgroundColor: 'rgba(52, 152, 219, 0.2)',
                tension: 0.4,
                fill: true
            }
        ]
    };
    
    // Failover events data
    const failoverEvents = [];
    let lastKnownStatus = {};
    
    // Initialize charts
    function initCharts() {
        // Availability chart
        const availabilityCtx = document.getElementById('availability-chart').getContext('2d');
        availabilityChart = new Chart(availabilityCtx, {
            type: 'line',
            data: availabilityData,
            options: {
                scales: {
                    y: {
                        beginAtZero: true,
                        max: 1,
                        ticks: {
                            callback: function(value) {
                                return value === 0 ? 'Down' : value === 1 ? 'Up' : '';
                            }
                        }
                    }
                },
                animation: {
                    duration: 500
                },
                plugins: {
                    legend: {
                        position: 'top',
                    }
                }
            }
        });
        
        // Failover chart
        const failoverCtx = document.getElementById('failover-chart').getContext('2d');
        failoverChart = new Chart(failoverCtx, {
            type: 'bar',
            data: {
                labels: ['Last 24 hours'],
                datasets: [
                    {
                        label: 'Failover Events',
                        data: [0],
                        backgroundColor: '#e74c3c'
                    }
                ]
            },
            options: {
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: {
                            stepSize: 1
                        }
                    }
                }
            }
        });
    }
    
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
        
        ws.onerror = function(error) {
            console.error('WebSocket error:', error);
            appendLogEntry('Error in dashboard connection. Retrying...');
        };
    }
    
    // Function to update the status display
    function updateStatusDisplay(status) {
        // Store last known status for comparison
        const oldStatus = {...lastKnownStatus};
        lastKnownStatus = status;
        
        // Update active service
        activeServiceElement.textContent = status.active_service.charAt(0).toUpperCase() + status.active_service.slice(1);
        activeServiceElement.className = 'status-indicator status-up';
        
        // Update service details
        primaryServiceElement.textContent = status.primary_service.charAt(0).toUpperCase() + status.primary_service.slice(1);
        failoverActiveElement.textContent = status.failover_active ? 'Yes' : 'No';
        
        if (status.last_failover) {
            lastFailoverElement.textContent = status.last_failover;
        }
        
        // Update health statuses
        updateHealthStatus(newtHealthElement, status.health.newt);
        updateHealthStatus(tailscaleHealthElement, status.health.tailscale);
        
        // Update availability chart
        updateAvailabilityChart(status);
        
        // Check for failover event
        if (oldStatus.active_service && oldStatus.active_service !== status.active_service) {
            // A failover occurred
            appendLogEntry(`Failover detected: ${oldStatus.active_service} → ${status.active_service}`);
            failoverEvents.push({
                timestamp: new Date(),
                from: oldStatus.active_service,
                to: status.active_service
            });
            
            // Update failover chart
            updateFailoverChart();
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
    
    // Function to update availability chart
    function updateAvailabilityChart(status) {
        // Update dataset values
        availabilityData.datasets[0].data.shift();
        availabilityData.datasets[1].data.shift();
        
        // Add new values
        availabilityData.datasets[0].data.push(status.health.newt === 'up' ? 1 : 0);
        availabilityData.datasets[1].data.push(status.health.tailscale === 'up' ? 1 : 0);
        
        // Update chart
        availabilityChart.update();
    }
    
    // Function to update failover chart
    function updateFailoverChart() {
        // Count failover events in the last 24 hours
        const last24Hours = new Date();
        last24Hours.setHours(last24Hours.getHours() - 24);
        
        const recentFailovers = failoverEvents.filter(event => event.timestamp > last24Hours).length;
        
        failoverChart.data.datasets[0].data = [recentFailovers];
        failoverChart.update();
    }
    
    // Function to update system info
    function updateSystemInfo(info) {
        cpuUsageElement.textContent = info.cpu;
        memoryUsageElement.textContent = info.memory.percentage + ' (' + info.memory.used + ' / ' + info.memory.total + ')';
        uptimeElement.textContent = formatUptime(info.uptime);
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
                logsData.logs.forEach(log => appendLogEntry(log));
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
    initCharts();
    fetchInitialData().then(() => {
        initWebSocket();
    });
});