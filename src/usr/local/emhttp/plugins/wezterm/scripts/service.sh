#!/bin/bash
#
# WezTerm Server Service Management Script
# Manages the wezterm-mux-server daemon on Unraid
#

# Paths
PLUGIN_DIR="/usr/local/emhttp/plugins/wezterm"
CONFIG_DIR="/boot/config/plugins/wezterm"
CONFIG_FILE="${CONFIG_DIR}/wezterm.cfg"
LUA_CONFIG="${CONFIG_DIR}/wezterm.lua"
PID_DIR="/var/run/wezterm"
PID_FILE="${PID_DIR}/wezterm-mux-server.pid"
GO_FILE="/boot/config/go"
SERVICE_NAME="wezterm"

# Default values
WEZTERM_BIN="/usr/local/bin/wezterm"
STOP_TIMEOUT=10

# Source configuration file if it exists
if [ -f "${CONFIG_FILE}" ]; then
    source "${CONFIG_FILE}"
fi

# Function to check if service is running
is_running() {
    if [ -f "${PID_FILE}" ]; then
        local pid=$(cat "${PID_FILE}")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            # PID file exists but process is not running
            rm -f "${PID_FILE}"
            return 1
        fi
    fi
    return 1
}

# Function to get PID
get_pid() {
    if [ -f "${PID_FILE}" ]; then
        cat "${PID_FILE}"
    fi
}

# Function to start the service
start() {
    if is_running; then
        local pid=$(get_pid)
        echo "WezTerm Server is already running (PID: $pid)"
        return 0
    fi

    echo "Starting WezTerm Server..."

    # Create PID directory if it doesn't exist
    if [ ! -d "${PID_DIR}" ]; then
        mkdir -p "${PID_DIR}"
        chmod 755 "${PID_DIR}"
    fi

    # Check if wezterm binary exists
    if [ ! -x "${WEZTERM_BIN}" ]; then
        echo "Error: WezTerm binary not found at ${WEZTERM_BIN}"
        return 1
    fi

    # Check if Lua config exists
    if [ ! -f "${LUA_CONFIG}" ]; then
        echo "Warning: Lua config not found at ${LUA_CONFIG}"
        echo "Creating default configuration..."
        mkdir -p "${CONFIG_DIR}"
        cat > "${LUA_CONFIG}" << 'EOF'
-- WezTerm Server Configuration
local wezterm = require 'wezterm'
local config = {}

-- Use config builder if available (WezTerm 20220101+)
if wezterm.config_builder then
  config = wezterm.config_builder()
end

-- Basic server settings
config.unix_domains = {
  {
    name = 'unix',
  },
}

-- Default to unix domain
config.default_gui_startup_args = { 'connect', 'unix' }

return config
EOF
    fi

    # Start wezterm-mux-server with daemonize option
    "${WEZTERM_BIN}" cli spawn --domain-name unix -- true 2>/dev/null || true
    "${WEZTERM_BIN}-mux-server" --daemonize --config-file "${LUA_CONFIG}" 2>&1

    # Give it a moment to start
    sleep 1

    # Find the PID using pgrep as a fallback
    local pid=$(pgrep -f "wezterm-mux-server.*${LUA_CONFIG}" | head -1)

    if [ -n "$pid" ]; then
        echo "$pid" > "${PID_FILE}"
        echo "WezTerm Server started successfully (PID: $pid)"
        return 0
    else
        echo "Error: Failed to start WezTerm Server"
        return 1
    fi
}

# Function to stop the service
stop() {
    if ! is_running; then
        echo "WezTerm Server is not running"
        # Clean up stale PID file if it exists
        rm -f "${PID_FILE}"
        return 0
    fi

    local pid=$(get_pid)
    echo "Stopping WezTerm Server (PID: $pid)..."

    # Send SIGTERM for graceful shutdown
    kill -TERM "$pid" 2>/dev/null

    # Wait for process to exit
    local count=0
    while kill -0 "$pid" 2>/dev/null && [ $count -lt $STOP_TIMEOUT ]; do
        sleep 1
        count=$((count + 1))
    done

    # Check if process is still running
    if kill -0 "$pid" 2>/dev/null; then
        echo "Process did not stop gracefully, sending SIGKILL..."
        kill -KILL "$pid" 2>/dev/null
        sleep 1
    fi

    # Remove PID file
    rm -f "${PID_FILE}"

    if kill -0 "$pid" 2>/dev/null; then
        echo "Error: Failed to stop WezTerm Server"
        return 1
    else
        echo "WezTerm Server stopped successfully"
        return 0
    fi
}

# Function to restart the service
restart() {
    echo "Restarting WezTerm Server..."
    stop
    sleep 2
    start
}

# Function to get service status
status() {
    local running="false"
    local pid=""

    if is_running; then
        running="true"
        pid=$(get_pid)
    fi

    # Output JSON for AJAX consumption
    echo "{\"running\": $running, \"pid\": \"$pid\"}"
}

# Function to enable service at boot
enable() {
    if [ ! -f "${GO_FILE}" ]; then
        echo "Creating go file at ${GO_FILE}"
        touch "${GO_FILE}"
        chmod +x "${GO_FILE}"
    fi

    # Check if already enabled
    if grep -q "${PLUGIN_DIR}/scripts/service.sh start" "${GO_FILE}"; then
        echo "WezTerm Server is already enabled at boot"
        return 0
    fi

    # Add start command to go file
    echo "" >> "${GO_FILE}"
    echo "# Start WezTerm Server" >> "${GO_FILE}"
    echo "${PLUGIN_DIR}/scripts/service.sh start" >> "${GO_FILE}"

    echo "WezTerm Server enabled at boot"

    # Update config file to reflect autostart status
    if [ -f "${CONFIG_FILE}" ]; then
        if grep -q "^AUTOSTART=" "${CONFIG_FILE}"; then
            sed -i 's/^AUTOSTART=.*/AUTOSTART="yes"/' "${CONFIG_FILE}"
        else
            echo 'AUTOSTART="yes"' >> "${CONFIG_FILE}"
        fi
    fi

    return 0
}

# Function to disable service at boot
disable() {
    if [ ! -f "${GO_FILE}" ]; then
        echo "WezTerm Server is not enabled at boot (go file does not exist)"
        return 0
    fi

    # Remove start command from go file
    if grep -q "${PLUGIN_DIR}/scripts/service.sh start" "${GO_FILE}"; then
        # Remove the line and the comment line before it if it exists
        sed -i "\|# Start WezTerm Server|d" "${GO_FILE}"
        sed -i "\|${PLUGIN_DIR}/scripts/service.sh start|d" "${GO_FILE}"
        echo "WezTerm Server disabled at boot"
    else
        echo "WezTerm Server is not enabled at boot"
    fi

    # Update config file to reflect autostart status
    if [ -f "${CONFIG_FILE}" ]; then
        if grep -q "^AUTOSTART=" "${CONFIG_FILE}"; then
            sed -i 's/^AUTOSTART=.*/AUTOSTART="no"/' "${CONFIG_FILE}"
        else
            echo 'AUTOSTART="no"' >> "${CONFIG_FILE}"
        fi
    fi

    return 0
}

# Function to display usage
usage() {
    echo "Usage: $0 {start|stop|restart|status|enable|disable}"
    echo ""
    echo "Commands:"
    echo "  start    - Start the WezTerm Server"
    echo "  stop     - Stop the WezTerm Server"
    echo "  restart  - Restart the WezTerm Server"
    echo "  status   - Check service status (JSON output)"
    echo "  enable   - Enable service at boot"
    echo "  disable  - Disable service at boot"
    exit 1
}

# Main script logic
case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    enable)
        enable
        ;;
    disable)
        disable
        ;;
    *)
        usage
        ;;
esac

exit $?
