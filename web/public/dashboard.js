// Enhanced Client-side Dashboard JavaScript
document.addEventListener('DOMContentLoaded', function() {
    // DOM Elements - Overview Tab
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
    
    // DOM Elements - Details Tab
    const detailPrimaryServiceElement = document.getElementById('detail-primary-service');
    const detailFailoverModeElement = document.getElementById('detail-failover-mode');
    const detailHealthCheckIntervalElement = document.getElementById('detail-health-check-interval');
    const detailHealthCheckFailuresElement = document.getElementById('detail-health-check-failures');
    const detailHealthCheckRecoveriesElement = document.getElementById('detail-health-check-recoveries');
    const detailNewtStatusElement = document.getElementById('detail-newt-status');
    const detailNewtConnectedSinceElement = document.getElementById('detail-newt-connected-since');
    const detailNewtEndpointElement = document.getElementById('detail-newt-endpoint');
    const detailTailscaleStatusElement = document.getElementById('detail-tailscale-status');
    const detailTailscaleConnectedSinceElement = document.getElementById('detail-tailscale-connected-since');
    const detailTailscaleRoutesElement = document.getElementById('detail-tailscale-routes');
    const portForwardingRulesElement = document.getElementById('port-forwarding-rules');
    
    // DOM Elements - Settings Tab
    const settingPrimaryServiceElement = document.getElementById('setting-primary-service');
    const settingFailoverModeElement = document.getElementById('setting-failover-mode');
    const settingHealthCheckIntervalElement = document.getElementById('setting-health-check-interval');
    const settingFailureThresholdElement = document.getElementById('setting-failure-threshold');
    const settingRecoveryThresholdElement = document.getElementById('setting-recovery-threshold');
    const settingEnableNotificationsElement = document.getElementById('setting-enable-notifications');
    const settingWebhookUrlElement = document.getElementById('setting-webhook-url');
    
    // Button Elements
    const refreshButton = document.getElementById('refresh-button');
    const manualFailoverButton = document.getElementById('manual-failover-button');
    const saveSettingsButton = document.getElementById('save-settings-button');
    const testNotificationButton = document.getElementById('test-notification-button');
    const saveNotificationSettingsButton = document.getElementById('save-notification-settings-button');
    const confirmFailoverButton = document.getElementById('confirm-failover-button');
    const cancelFailoverButton = document.getElementById('cancel-failover-button');
    
    // Modal Elements
    const manualFailoverModal = document.getElementById('manual-failover-modal');
    const modalCloseButton = document.querySelector('.modal-close');
    const modalFromServiceElement = document.getElementById('modal-from-service');
    const modalToServiceElement = document.getElementById('modal-to-service');
    
    // Tab Navigation
    const tabButtons = document.querySelectorAll('.tab-button');
    const tabContents = document.querySelectorAll('.tab-content');
    
    // Log Filter Buttons
    const logFilterButtons = document.querySelectorAll('.log-level-filter');
    
    // Charts
    let availabilityChart;
    let failoverChart;
    
    // State
    let currentStatus = {
        active_service: '',
        primary_service: '',
        failover_active: false,
        last_failover: null,
        health: {
            newt: 'unknown',
            tailscale: 'unknown'
        }
    };
    
    let config = {
        primary_service: '',
        failover_mode: '',
        health_check_interval: 10,
        health_check_failures_threshold: 3,
        health_check_recovery_threshold: 5,
        enable_notifications: false,
        webhook_url: ''
    };
    
    // Availability data
    const availabilityData = {
        labels: Array.from({length: 20}, (_, i) => ''),
        datasets: [
            {
                label: 'Newt',
                data: Array(20).fill(null),
                borderColor: '#10b981',
                backgroundColor: 'rgba(16, 185, 129, 0.2)',
                tension: 0.4,
                fill: true
            },
            {
                label: 'Tailscale',
                data: Array(20).fill(null),
                borderColor: '#3b82f6',
                backgroundColor: 'rgba(59, 130, 246, 0.2)',
                tension: 0.4,
                fill: true
            }
        ]
    };
    
    // Failover events data
    const failoverEvents = [];
    
    // Initialize tabs
    function initTabs() {
        tabButtons.forEach(button => {
            button.addEventListener('click', () => {
                // Remove active class from all buttons and contents
                tabButtons.forEach(btn => btn.classList.remove('active'));
                tabContents.forEach(content => content.classList.remove('active'));
                
                // Add active class to clicked button and corresponding content
                button.classList.add('active');
                const tabId = button.dataset.tab;
                document.getElementById(`${tabId}-tab`).classList.add('active');
            });
        });
    }
    
    // Initialize log filters
    function initLogFilters() {
        logFilterButtons.forEach(button => {
            button.addEventListener('click', () => {
                // Toggle active class
                logFilterButtons.forEach(btn => btn.classList.remove('active'));
                button.classList.add('active');
                
                // Apply filter
                const level = button.dataset.level;
                filterLogs(level);
            });
        });
    }
    
    // Filter logs by level
    function filterLogs(level) {
        const logEntries = document.querySelectorAll('.log-entry');
        
        if (level === 'all') {
            logEntries.forEach(entry => {
                entry.style.display = 'block';
            });
        } else {
            logEntries.forEach(entry => {
                if (entry.classList.contains(level)) {
                    entry.style.display = 'block';
                } else {
                    entry.style.display = 'none';
                }
            });
        }
    }
    
    // Initialize modal
    function initModal() {
        // Open modal
        manualFailoverButton.addEventListener('click', () => {
            modalFromServiceElement.textContent = currentStatus.active_service;
            modalToServiceElement.textContent = currentStatus.active_service === 'newt' ? 'tailscale' : 'newt';
            manualFailoverModal.classList.add('active');
        });
        
        // Close modal
        modalCloseButton.addEventListener('click', () => {
            manualFailoverModal.classList.remove('active');
        });
        
        // Close modal when clicking outside
        window.addEventListener('click', (event) => {
            if (event.target === manualFailoverModal) {
                manualFailoverModal.classList.remove('active');
            }
        });
        
        // Cancel button
        cancelFailoverButton.addEventListener('click', () => {
            manualFailoverModal.classList.remove('active');
        });
        
        // Confirm button
        confirmFailoverButton.addEventListener('click', () => {
            triggerManualFailover();
            manualFailoverModal.classList.remove('active');
        });
    }
    
    // Trigger manual failover
    function triggerManualFailover() {
        const fromService = currentStatus.active_service;
        const toService = fromService === 'newt' ? 'tailscale' : 'newt';
        
        // This is a simple implementation - in a real system you would call an API endpoint
        appendLogEntry(`Manual failover triggered from ${fromService} to ${toService}`);
        
        // Simulate API call
        fetch('/api/manual-failover', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                from_service: fromService,
                to_service: toService
            })
        }).then(response => {
            if (!response.ok) {
                throw new Error('Failed to trigger manual failover');
            }
            return response.json();
        }).then(data => {
            appendLogEntry(`Manual failover completed: ${data.message}`);
        }).catch(error => {
            appendLogEntry(`Error triggering manual failover: ${error.message}`, 'error');
        });
    }
    
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
                    },
                    x: {
                        ticks: {
                            maxRotation: 0,
                            autoSkip: true,
                            maxTicksLimit: 10
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
                },
                responsive: true,
                maintainAspectRatio: false
            }
        });
        
        // Failover chart
        const failoverCtx = document.getElementById('failover-chart').getContext('2d');
        failoverChart = new Chart(failoverCtx, {
            type: 'bar',
            data: {
                labels: ['Last Hour', '2-6 Hours', '6-12 Hours', '12-24 Hours'],
                datasets: [
                    {
                        label: 'Failover Events',
                        data: [0, 0, 0, 0],
                        backgroundColor: '#ef4444'
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
                },
                plugins: {
                    legend: {
                        display: false
                    }
                },
                responsive: true,
                maintainAspectRatio: false
            }
        });
    }
    
    // Initialize WebSocket connection
    function initWebSocket() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const ws = new WebSocket(`${protocol}//${window.location.host}/api/live`);
        
        ws.onopen = function() {
            console.log('WebSocket connection established');
            appendLogEntry('Connected to live updates');
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
                case 'logs':
                    // Handle multiple logs at once (initial load)
                    if (Array.isArray(message.data)) {
                        message.data.forEach(log => appendLogEntry(log));
                    }
                    break;
                case 'system':
                    updateSystemInfo(message.data);
                    break;
                case 'services':
                    updateServicesStatus(message.data);
                    break;
                case 'config':
                    updateConfigDisplay(message.data);
                    break;
                case 'port_forwarding':
                    updatePortForwarding(message.data);
                    break;
            }
        };
        
        ws.onclose = function() {
            console.log('WebSocket connection closed');
            appendLogEntry('Disconnected from live updates. Reconnecting in 5 seconds...', 'warning');
            setTimeout(initWebSocket, 5000);
        };
        
        ws.onerror = function(error) {
            console.error('WebSocket error:', error);
            appendLogEntry('Error in dashboard connection. Retrying...', 'error');
        };
        
        return ws;
    }
    
    // Function to update services status display
    function updateServicesStatus(status) {
        if (!status) return;
        
        if (status.newt) {
            const statusClass = status.newt === 'running' ? 'status-up' : 'status-down';
            newtHealthElement.className = `health-status ${statusClass}`;
            detailNewtStatusElement.innerHTML = status.newt === 'running' ? 
                '<span class="badge badge-success">Running</span>' : 
                '<span class="badge badge-danger">Stopped</span>';
        }
        
        if (status.tailscale) {
            const statusClass = status.tailscale === 'running' ? 'status-up' : 'status-down';
            tailscaleHealthElement.className = `health-status ${statusClass}`;
            detailTailscaleStatusElement.innerHTML = status.tailscale === 'running' ? 
                '<span class="badge badge-success">Running</span>' : 
                '<span class="badge badge-danger">Stopped</span>';
        }
    }
    
    // Function to update port forwarding rules
    function updatePortForwarding(data) {
        if (!data || !data.rules || !data.rules.length) {
            portForwardingRulesElement.innerHTML = '<p>No port forwarding rules configured</p>';
            return;
        }
        
        let html = '';
        data.rules.forEach(rule => {
            html += `<p><span>Port ${rule.port}:</span> <span>${rule.source} → ${rule.destination}</span></p>`;
        });
        
        portForwardingRulesElement.innerHTML = html;
    }
    
    // Function to update config display
    function updateConfigDisplay(config) {
        if (!config) return;
        
        // Update details tab
        if (detailPrimaryServiceElement) {
            detailPrimaryServiceElement.textContent = config.primary_service ? 
                (config.primary_service.charAt(0).toUpperCase() + config.primary_service.slice(1)) : 'Unknown';
        }
        
        if (detailFailoverModeElement) {
            detailFailoverModeElement.textContent = config.failover_mode ? 
                (config.failover_mode.charAt(0).toUpperCase() + config.failover_mode.slice(1)) : 'Unknown';
        }
        
        if (detailHealthCheckIntervalElement) {
            detailHealthCheckIntervalElement.textContent = config.health_check_interval ? 
                `${config.health_check_interval} seconds` : 'Unknown';
        }
        
        if (detailHealthCheckFailuresElement) {
            detailHealthCheckFailuresElement.textContent = config.health_check_failures_threshold || 'Unknown';
        }
        
        if (detailHealthCheckRecoveriesElement) {
            detailHealthCheckRecoveriesElement.textContent = config.health_check_recovery_threshold || 'Unknown';
        }
        
        // Update settings tab
        if (settingPrimaryServiceElement) {
            settingPrimaryServiceElement.value = config.primary_service || 'newt';
        }
        
        if (settingFailoverModeElement) {
            settingFailoverModeElement.value = config.failover_mode || 'immediate';
        }
        
        if (settingHealthCheckIntervalElement) {
            settingHealthCheckIntervalElement.value = config.health_check_interval || 10;
        }
        
        if (settingFailureThresholdElement) {
            settingFailureThresholdElement.value = config.health_check_failures_threshold || 3;
        }
        
        if (settingRecoveryThresholdElement) {
            settingRecoveryThresholdElement.value = config.health_check_recovery_threshold || 5;
        }
        
        if (settingEnableNotificationsElement) {
            settingEnableNotificationsElement.checked = config.enable_notifications || false;
        }
        
        if (settingWebhookUrlElement) {
            settingWebhookUrlElement.value = config.webhook_url || '';
        }
    }
    
    // Function to update the status display
    function updateStatusDisplay(status) {
        if (!status) return;
        
        // Store last status for comparison
        const oldStatus = {...currentStatus};
        currentStatus = status;
        
        // Update active service
        if (activeServiceElement) {
            activeServiceElement.textContent = status.active_service ? 
                (status.active_service.charAt(0).toUpperCase() + status.active_service.slice(1)) : 'Unknown';
            activeServiceElement.className = `status-indicator status-${status.active_service === 'newt' ? 'up' : 'standby'}`;
        }
        
        // Update service details
        if (primaryServiceElement) {
            primaryServiceElement.textContent = status.primary_service ? 
                (status.primary_service.charAt(0).toUpperCase() + status.primary_service.slice(1)) : 'Unknown';
        }
        
        if (failoverActiveElement) {
            failoverActiveElement.textContent = status.failover_active ? 'Yes' : 'No';
            failoverActiveElement.className = status.failover_active ? 'badge badge-warning' : 'badge badge-success';
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
        
        // Update connected since for services
        if (detailNewtConnectedSinceElement) {
            detailNewtConnectedSinceElement.textContent = status.newt_connected_since || 'Not connected';
        }
        
        if (detailTailscaleConnectedSinceElement) {
            detailTailscaleConnectedSinceElement.textContent = status.tailscale_connected_since || 'Not connected';
        }
        
        // Update endpoint info
        if (detailNewtEndpointElement) {
            detailNewtEndpointElement.textContent = status.newt_endpoint || 'Unknown';
        }
        
        if (detailTailscaleRoutesElement) {
            detailTailscaleRoutesElement.textContent = status.tailscale_routes || 'None';
        }
        
        // Update availability chart
        updateAvailabilityChart(status);
        
        // Check for failover event
        if (oldStatus.active_service && oldStatus.active_service !== status.active_service) {
            // A failover occurred
            appendLogEntry(`Failover detected: ${oldStatus.active_service} → ${status.active_service}`, 'warning');
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
        
        // Add timestamp as label
        const now = new Date();
        const timeString = now.getHours().toString().padStart(2, '0') + ':' + 
                          now.getMinutes().toString().padStart(2, '0') + ':' + 
                          now.getSeconds().toString().padStart(2, '0');
        
        availabilityData.labels.shift();
        availabilityData.labels.push(timeString);
        
        // Update chart
        availabilityChart.update();
    }
    
    // Function to update failover chart
    function updateFailoverChart() {
        // Get current time
        const now = new Date();
        
        // Count failover events in different time buckets
        const lastHour = new Date(now - 3600000); // Last hour
        const last6Hours = new Date(now - 21600000); // Last 6 hours
        const last12Hours = new Date(now - 43200000); // Last 12 hours
        const last24Hours = new Date(now - 86400000); // Last 24 hours
        
        const counts = [0, 0, 0, 0]; // [Last Hour, 2-6 Hours, 6-12 Hours, 12-24 Hours]
        
        failoverEvents.forEach(event => {
            if (event.timestamp > lastHour) {
                counts[0]++;
            } else if (event.timestamp > last6Hours) {
                counts[1]++;
            } else if (event.timestamp > last12Hours) {
                counts[2]++;
            } else if (event.timestamp > last24Hours) {
                counts[3]++;
            }
        });
        
        failoverChart.data.datasets[0].data = counts;
        failoverChart.update();
    }
    
    // Function to update system info
    function updateSystemInfo(info) {
        if (cpuUsageElement) {
            cpuUsageElement.textContent = info.cpu || '0%';
        }
        
        if (memoryUsageElement) {
            memoryUsageElement.textContent = info.memory ? 
                `${info.memory.percentage} (${info.memory.used} / ${info.memory.total})` : 
                'Loading...';
        }
        
        if (uptimeElement) {
            uptimeElement.textContent = formatUptime(info.uptime || '0');
        }
    }
    
    // Function to format uptime string
    function formatUptime(uptime) {
        const uptimeSeconds = parseFloat(uptime);
        
        const days = Math.floor(uptimeSeconds / 86400);
        const hours = Math.floor((uptimeSeconds % 86400) / 3600);
        const minutes = Math.floor((uptimeSeconds % 3600) / 60);
        const seconds = Math.floor(uptimeSeconds % 60);
        
        let result = '';
        if (days > 0) result += `${days}d `;
        if (hours > 0 || days > 0) result += `${hours}h `;
        if (minutes > 0 || hours > 0 || days > 0) result += `${minutes}m `;
        result += `${seconds}s`;
        
        return result;
    }
    
    // Function to append log entry
    function appendLogEntry(entry, level = 'info') {
        if (!entry || entry.trim() === '') return;
        if (!logEntriesElement) return;
        
        // Parse log entry if it's a string with timestamp
        let message = entry;
        let timestamp = new Date().toISOString().replace('T', ' ').substr(0, 19);
        
        if (typeof entry === 'string' && entry.startsWith('[') && entry.includes(']')) {
            const parts = entry.match(/\[(.*?)\] (.*)/);
            if (parts && parts.length > 2) {
                timestamp = parts[1];
                message = parts[2];
            }
        }
        
        // Detect log level from message
        if (typeof entry === 'string') {
            if (entry.toLowerCase().includes('error') || entry.toLowerCase().includes('fail')) {
                level = 'error';
            } else if (entry.toLowerCase().includes('warn')) {
                level = 'warning';
            }
        }
        
        const logEntry = document.createElement('div');
        logEntry.className = `log-entry ${level}`;
        logEntry.innerHTML = `<span class="timestamp">${timestamp}</span> ${message}`;
        logEntriesElement.appendChild(logEntry);
        
        // Auto-scroll to bottom
        logEntriesElement.scrollTop = logEntriesElement.scrollHeight;
        
        // Limit to 500 entries
        while (logEntriesElement.children.length > 500) {
            logEntriesElement.removeChild(logEntriesElement.firstChild);
        }
        
        // Apply current filter
        const activeFilter = document.querySelector('.log-level-filter.active');
        if (activeFilter) {
            filterLogs(activeFilter.dataset.level);
        }
    }
    
    // Save settings
    function saveSettings() {
        const newSettings = {
            primary_service: settingPrimaryServiceElement.value,
            failover_mode: settingFailoverModeElement.value,
            health_check_interval: parseInt(settingHealthCheckIntervalElement.value, 10),
            health_check_failures_threshold: parseInt(settingFailureThresholdElement.value, 10),
            health_check_recovery_threshold: parseInt(settingRecoveryThresholdElement.value, 10)
        };
        
        // Validate settings
        if (isNaN(newSettings.health_check_interval) || newSettings.health_check_interval < 1) {
            appendLogEntry('Invalid health check interval', 'error');
            return;
        }
        
        if (isNaN(newSettings.health_check_failures_threshold) || newSettings.health_check_failures_threshold < 1) {
            appendLogEntry('Invalid failure threshold', 'error');
            return;
        }
        
        if (isNaN(newSettings.health_check_recovery_threshold) || newSettings.health_check_recovery_threshold < 1) {
            appendLogEntry('Invalid recovery threshold', 'error');
            return;
        }
        
        // Simulate API call to save settings
        fetch('/api/config', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(newSettings)
        }).then(response => {
            if (!response.ok) {
                throw new Error('Failed to save settings');
            }
            return response.json();
        }).then(data => {
            appendLogEntry(`Settings saved successfully: ${data.message}`);
        }).catch(error => {
            appendLogEntry(`Error saving settings: ${error.message}`, 'error');
        });
    }
    
    // Save notification settings
    function saveNotificationSettings() {
        const newSettings = {
            enable_notifications: settingEnableNotificationsElement.checked,
            webhook_url: settingWebhookUrlElement.value
        };
        
        // Validate settings
        if (newSettings.enable_notifications && !newSettings.webhook_url) {
            appendLogEntry('Webhook URL is required when notifications are enabled', 'error');
            return;
        }
        
        // Simulate API call to save settings
        fetch('/api/notification-config', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(newSettings)
        }).then(response => {
            if (!response.ok) {
                throw new Error('Failed to save notification settings');
            }
            return response.json();
        }).then(data => {
            appendLogEntry(`Notification settings saved successfully: ${data.message}`);
        }).catch(error => {
            appendLogEntry(`Error saving notification settings: ${error.message}`, 'error');
        });
    }
    
    // Test notification
    function testNotification() {
        // Simulate API call to test notification
        fetch('/api/test-notification', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                webhook_url: settingWebhookUrlElement.value
            })
        }).then(response => {
            if (!response.ok) {
                throw new Error('Failed to test notification');
            }
            return response.json();
        }).then(data => {
            appendLogEntry(`Test notification sent successfully: ${data.message}`);
        }).catch(error => {
            appendLogEntry(`Error sending test notification: ${error.message}`, 'error');
        });
    }
    
    // Function to fetch initial data (fallback if WebSocket fails)
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
            
            // Fetch config
            const configResponse = await fetch('/api/config');
            if (configResponse.ok) {
                const configData = await configResponse.json();
                updateConfigDisplay(configData);
            }
            
            // Fetch port forwarding rules
            const portForwardingResponse = await fetch('/api/port-forwarding');
            if (portForwardingResponse.ok) {
                const portForwardingData = await portForwardingResponse.json();
                updatePortForwarding(portForwardingData);
            }
        } catch (error) {
            console.error('Error fetching initial data:', error);
            appendLogEntry('Error fetching initial data. Will retry with live updates.', 'error');
        }
    }
    
    // Initialize the application
    function init() {
        // Initialize UI components
        initTabs();
        initLogFilters();
        initCharts();
        initModal();
        
        // Set up event listeners
        if (refreshButton) {
            refreshButton.addEventListener('click', fetchInitialData);
        }
        
        if (saveSettingsButton) {
            saveSettingsButton.addEventListener('click', saveSettings);
        }
        
        if (saveNotificationSettingsButton) {
            saveNotificationSettingsButton.addEventListener('click', saveNotificationSettings);
        }
        
        if (testNotificationButton) {
            testNotificationButton.addEventListener('click', testNotification);
        }
        
        // Fetch initial data and set up WebSocket
        fetchInitialData();
        const socket = initWebSocket();
        
        // Fallback to REST API if WebSocket fails to connect within 3 seconds
        const wsTimeout = setTimeout(() => {
            if (socket.readyState !== 1) { // 1 = WebSocket.OPEN
                fetchInitialData();
            }
        }, 3000);
        
        // Clear timeout if WebSocket connects successfully
        socket.addEventListener('open', () => {
            clearTimeout(wsTimeout);
        });
        
        // Setup periodic refresh as a backup to WebSocket
        setInterval(fetchInitialData, 60000);
    }
    
    // Start the application
    init();
});