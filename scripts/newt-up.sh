#!/bin/bash
set -e

# Check if Newt is enabled
if [ "${ENABLE_NEWT}" != "true" ]; then
    echo "Newt tunnel is disabled. Exiting."
    exit 0
fi

# Check for credentials
if [ -z "${NEWT_ID}" ] || [ -z "${NEWT_SECRET}" ] || [ -z "${PANGOLIN_ENDPOINT}" ]; then
    echo "Error: Newt is enabled but required parameters are missing"
    echo "Please set NEWT_ID, NEWT_SECRET, and PANGOLIN_ENDPOINT in your .env file"
    exit 1
fi

# Start Newt client
echo "Starting Newt client..."

# Note: Using the flags that are actually supported by the newt binary
# Additional configuration may need to be provided differently based on newt documentation
exec newt "${NEWT_ID}" "${NEWT_SECRET}" "${PANGOLIN_ENDPOINT}"

# Alternative approach if newt expects positional arguments instead of flags:
# exec newt "${NEWT_ID}" "${NEWT_SECRET}" "${PANGOLIN_ENDPOINT}"