<?php
/**
 * WezTerm Server Plugin - Helper Functions
 *
 * This file contains all helper functions for managing the WezTerm
 * multiplexer server on Unraid.
 */

// Constants
define('WEZTERM_CONFIG_FILE', '/boot/config/plugins/wezterm/wezterm.cfg');
define('WEZTERM_CERTS_DIR', '/boot/config/plugins/wezterm/certs');
define('WEZTERM_CLIENTS_DIR', '/boot/config/plugins/wezterm/certs/clients');
define('WEZTERM_PID_FILE', '/var/run/wezterm/wezterm-mux-server.pid');
define('WEZTERM_LUA_CONFIG', '/boot/config/plugins/wezterm/wezterm.lua');

/**
 * Read WezTerm configuration from file
 *
 * @return array Associative array with configuration keys
 */
function wezterm_read_config() {
    $defaults = [
        'SERVICE' => 'disable',
        'LISTEN_ADDRESS' => '0.0.0.0',
        'LISTEN_PORT' => '8080',
        'LOG_LEVEL' => 'info',
        'VERSION' => ''
    ];

    if (!file_exists(WEZTERM_CONFIG_FILE)) {
        return $defaults;
    }

    $config = $defaults;
    $lines = file(WEZTERM_CONFIG_FILE, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);

    if ($lines === false) {
        return $defaults;
    }

    foreach ($lines as $line) {
        $line = trim($line);

        // Skip comments
        if (empty($line) || $line[0] === '#') {
            continue;
        }

        // Parse KEY="value" format
        if (preg_match('/^([A-Z_]+)="(.*)"\s*$/', $line, $matches)) {
            $key = $matches[1];
            $value = $matches[2];

            if (array_key_exists($key, $config)) {
                $config[$key] = $value;
            }
        }
    }

    return $config;
}

/**
 * Write WezTerm configuration to file
 *
 * @param array $config Configuration array
 * @return bool Success status
 */
function wezterm_write_config($config) {
    $config_dir = dirname(WEZTERM_CONFIG_FILE);

    // Create directory if it doesn't exist
    if (!is_dir($config_dir)) {
        if (!mkdir($config_dir, 0755, true)) {
            error_log("Failed to create config directory: $config_dir");
            return false;
        }
    }

    // Build configuration content
    $content = "# WezTerm Server Configuration\n";
    $content .= "# Generated on " . date('Y-m-d H:i:s') . "\n\n";

    $allowed_keys = ['SERVICE', 'LISTEN_ADDRESS', 'LISTEN_PORT', 'LOG_LEVEL', 'VERSION'];

    foreach ($allowed_keys as $key) {
        if (isset($config[$key])) {
            $value = $config[$key];
            $content .= "$key=\"$value\"\n";
        }
    }

    // Write to file
    $result = file_put_contents(WEZTERM_CONFIG_FILE, $content);

    if ($result === false) {
        error_log("Failed to write config file: " . WEZTERM_CONFIG_FILE);
        return false;
    }

    return true;
}

/**
 * Get WezTerm server status
 *
 * @return array Status information with 'running' and 'pid' keys
 */
function wezterm_get_status() {
    $status = [
        'running' => false,
        'pid' => null
    ];

    // First check PID file
    if (file_exists(WEZTERM_PID_FILE)) {
        $pid = trim(file_get_contents(WEZTERM_PID_FILE));

        if (is_numeric($pid) && $pid > 0) {
            // Verify process is actually running
            if (file_exists("/proc/$pid")) {
                $status['running'] = true;
                $status['pid'] = (int)$pid;
                return $status;
            }
        }
    }

    // Fallback to pgrep
    $output = [];
    exec('pgrep -f "wezterm-mux-server" 2>/dev/null', $output, $return_code);

    if ($return_code === 0 && !empty($output)) {
        $status['running'] = true;
        $status['pid'] = (int)$output[0];
    }

    return $status;
}

/**
 * Get WezTerm version
 *
 * @return string Version string or "Not installed"
 */
function wezterm_get_version() {
    $binary = '/usr/local/bin/wezterm-mux-server';

    if (!file_exists($binary)) {
        return 'Not installed';
    }

    $output = [];
    exec("$binary --version 2>&1", $output, $return_code);

    if ($return_code !== 0 || empty($output)) {
        return 'Unknown';
    }

    $version_line = $output[0];

    // Parse version from output like "wezterm-mux-server 20230408-112425-69ae8472"
    if (preg_match('/wezterm[^\s]*\s+(.+)/', $version_line, $matches)) {
        return trim($matches[1]);
    }

    return trim($version_line);
}

/**
 * Check if CA is initialized
 *
 * @return bool True if CA certificate exists
 */
function wezterm_ca_initialized() {
    $ca_cert = WEZTERM_CERTS_DIR . '/ca.crt';
    $ca_key = WEZTERM_CERTS_DIR . '/ca.key';

    return file_exists($ca_cert) && file_exists($ca_key);
}

/**
 * List all client certificates
 *
 * @return array Array of certificate information
 */
function wezterm_list_certs() {
    $certs = [];

    if (!is_dir(WEZTERM_CLIENTS_DIR)) {
        return $certs;
    }

    $revoked_certs = wezterm_get_revoked_certs();

    $files = glob(WEZTERM_CLIENTS_DIR . '/*.crt');

    if ($files === false) {
        return $certs;
    }

    foreach ($files as $cert_file) {
        $name = basename($cert_file, '.crt');

        // Get file creation time
        $created_time = filectime($cert_file);
        $created_date = date('Y-m-d', $created_time);

        // Check if revoked
        $is_revoked = in_array($name, $revoked_certs);

        $certs[] = [
            'name' => $name,
            'created' => $created_date,
            'revoked' => $is_revoked,
            'file' => $cert_file
        ];
    }

    // Sort by creation date, newest first
    usort($certs, function($a, $b) {
        return strcmp($b['created'], $a['created']);
    });

    return $certs;
}

/**
 * Get revoked certificate list
 *
 * @return array Array of revoked certificate names
 */
function wezterm_get_revoked_certs() {
    $revoked_file = WEZTERM_CERTS_DIR . '/revoked.txt';

    if (!file_exists($revoked_file)) {
        return [];
    }

    $content = file_get_contents($revoked_file);

    if ($content === false) {
        return [];
    }

    $lines = explode("\n", trim($content));
    $revoked = [];

    foreach ($lines as $line) {
        $line = trim($line);
        if (!empty($line) && $line[0] !== '#') {
            $revoked[] = $line;
        }
    }

    return $revoked;
}

/**
 * Get detailed information about a specific certificate
 *
 * @param string $name Certificate name (without .crt extension)
 * @return array|null Certificate details or null if not found
 */
function wezterm_get_cert_info($name) {
    $cert_file = WEZTERM_CLIENTS_DIR . '/' . $name . '.crt';

    if (!file_exists($cert_file)) {
        return null;
    }

    $info = [
        'name' => $name,
        'file' => $cert_file,
        'subject' => '',
        'issuer' => '',
        'valid_from' => '',
        'valid_to' => '',
        'fingerprint' => '',
        'serial' => ''
    ];

    // Get certificate details using openssl
    $output = [];
    exec("openssl x509 -in " . escapeshellarg($cert_file) . " -noout -subject 2>/dev/null", $output);
    if (!empty($output)) {
        $info['subject'] = trim(str_replace('subject=', '', $output[0]));
    }

    $output = [];
    exec("openssl x509 -in " . escapeshellarg($cert_file) . " -noout -issuer 2>/dev/null", $output);
    if (!empty($output)) {
        $info['issuer'] = trim(str_replace('issuer=', '', $output[0]));
    }

    $output = [];
    exec("openssl x509 -in " . escapeshellarg($cert_file) . " -noout -startdate 2>/dev/null", $output);
    if (!empty($output)) {
        $date_str = str_replace('notBefore=', '', $output[0]);
        $timestamp = strtotime($date_str);
        if ($timestamp !== false) {
            $info['valid_from'] = date('Y-m-d H:i:s', $timestamp);
        }
    }

    $output = [];
    exec("openssl x509 -in " . escapeshellarg($cert_file) . " -noout -enddate 2>/dev/null", $output);
    if (!empty($output)) {
        $date_str = str_replace('notAfter=', '', $output[0]);
        $timestamp = strtotime($date_str);
        if ($timestamp !== false) {
            $info['valid_to'] = date('Y-m-d H:i:s', $timestamp);
        }
    }

    $output = [];
    exec("openssl x509 -in " . escapeshellarg($cert_file) . " -noout -fingerprint -sha256 2>/dev/null", $output);
    if (!empty($output)) {
        $info['fingerprint'] = trim(str_replace('SHA256 Fingerprint=', '', $output[0]));
    }

    $output = [];
    exec("openssl x509 -in " . escapeshellarg($cert_file) . " -noout -serial 2>/dev/null", $output);
    if (!empty($output)) {
        $info['serial'] = trim(str_replace('serial=', '', $output[0]));
    }

    return $info;
}

/**
 * Generate WezTerm Lua configuration file
 *
 * @param array $config Configuration array with LISTEN_ADDRESS and LISTEN_PORT
 * @return bool Success status
 */
function wezterm_generate_lua_config($config) {
    $listen_address = isset($config['LISTEN_ADDRESS']) ? $config['LISTEN_ADDRESS'] : '0.0.0.0';
    $listen_port = isset($config['LISTEN_PORT']) ? $config['LISTEN_PORT'] : '8080';

    $lua_content = <<<LUA
-- WezTerm Multiplexer Server Configuration
-- Generated on {DATE}

local wezterm = require 'wezterm'
local config = {}

-- Multiplexer server configuration
config.unix_domains = {}
config.ssh_domains = {}

-- TLS configuration for secure connections
config.tls_servers = {
  {
    -- Bind to configured address and port
    bind_address = "$listen_address:$listen_port",

    -- Certificate paths
    pem_cert = "/boot/config/plugins/wezterm/certs/server.crt",
    pem_private_key = "/boot/config/plugins/wezterm/certs/server.key",
    pem_ca = "/boot/config/plugins/wezterm/certs/ca.crt",

    -- Require client certificates for authentication
    pem_root_certs = "/boot/config/plugins/wezterm/certs/ca.crt",
  },
}

return config

LUA;

    // Replace date placeholder
    $lua_content = str_replace('{DATE}', date('Y-m-d H:i:s'), $lua_content);

    $config_dir = dirname(WEZTERM_LUA_CONFIG);

    // Create directory if it doesn't exist
    if (!is_dir($config_dir)) {
        if (!mkdir($config_dir, 0755, true)) {
            error_log("Failed to create config directory: $config_dir");
            return false;
        }
    }

    // Write configuration file
    $result = file_put_contents(WEZTERM_LUA_CONFIG, $lua_content);

    if ($result === false) {
        error_log("Failed to write Lua config file: " . WEZTERM_LUA_CONFIG);
        return false;
    }

    return true;
}

/**
 * Format file size in human-readable format
 *
 * @param int $bytes File size in bytes
 * @return string Formatted size string
 */
function wezterm_format_bytes($bytes) {
    $units = ['B', 'KB', 'MB', 'GB', 'TB'];

    $bytes = max($bytes, 0);
    $pow = floor(($bytes ? log($bytes) : 0) / log(1024));
    $pow = min($pow, count($units) - 1);

    $bytes /= pow(1024, $pow);

    return round($bytes, 2) . ' ' . $units[$pow];
}

/**
 * Validate IP address or hostname
 *
 * @param string $address Address to validate
 * @return bool True if valid
 */
function wezterm_validate_address($address) {
    // Check if valid IP address
    if (filter_var($address, FILTER_VALIDATE_IP)) {
        return true;
    }

    // Check if valid hostname (basic check)
    if (preg_match('/^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$/', $address)) {
        return true;
    }

    return false;
}

/**
 * Validate port number
 *
 * @param mixed $port Port number to validate
 * @return bool True if valid
 */
function wezterm_validate_port($port) {
    if (!is_numeric($port)) {
        return false;
    }

    $port = (int)$port;

    return $port >= 1 && $port <= 65535;
}

/**
 * Sanitize certificate name
 *
 * @param string $name Certificate name
 * @return string Sanitized name
 */
function wezterm_sanitize_cert_name($name) {
    // Remove any characters that aren't alphanumeric, dash, or underscore
    $name = preg_replace('/[^a-zA-Z0-9\-_]/', '', $name);

    // Limit length
    $name = substr($name, 0, 64);

    return $name;
}

/**
 * Get plugin version from plg file
 *
 * @return string Plugin version
 */
function wezterm_get_plugin_version() {
    $plg_file = '/boot/config/plugins/wezterm.plg';

    if (!file_exists($plg_file)) {
        return 'Unknown';
    }

    $content = file_get_contents($plg_file);

    if ($content === false) {
        return 'Unknown';
    }

    // Parse XML to get version
    if (preg_match('/<version>(.*?)<\/version>/', $content, $matches)) {
        return $matches[1];
    }

    return 'Unknown';
}

/**
 * Check if a port is in use
 *
 * @param int $port Port number to check
 * @return bool True if port is in use
 */
function wezterm_is_port_in_use($port) {
    $output = [];
    exec("netstat -tuln 2>/dev/null | grep -w " . escapeshellarg($port), $output);

    return !empty($output);
}

/**
 * Get system information for diagnostics
 *
 * @return array System information
 */
function wezterm_get_system_info() {
    $info = [
        'plugin_version' => wezterm_get_plugin_version(),
        'wezterm_version' => wezterm_get_version(),
        'config_exists' => file_exists(WEZTERM_CONFIG_FILE),
        'ca_initialized' => wezterm_ca_initialized(),
        'certs_dir_writable' => is_writable(dirname(WEZTERM_CERTS_DIR)),
        'openssl_available' => !empty(shell_exec('which openssl 2>/dev/null')),
        'status' => wezterm_get_status()
    ];

    return $info;
}
