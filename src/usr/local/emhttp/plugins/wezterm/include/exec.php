<?php
/**
 * WezTerm Server Plugin - AJAX Action Handler
 *
 * Handles all AJAX requests from the web UI for managing the WezTerm server
 *
 * @package WezTermServer
 * @version 1.0.0
 */

// Security: Ensure this is only called via POST/GET
if (!isset($_SERVER['REQUEST_METHOD'])) {
    http_response_code(403);
    die('Direct access not permitted');
}

// Include helper functions
require_once __DIR__ . '/helpers.php';

// Plugin paths
const PLUGIN_DIR = '/usr/local/emhttp/plugins/wezterm';
const SCRIPTS_DIR = PLUGIN_DIR . '/scripts';
const CONFIG_DIR = '/boot/config/plugins/wezterm';
const CERTS_DIR = CONFIG_DIR . '/certs';
const CONFIG_FILE = CONFIG_DIR . '/wezterm.cfg';
const WEZTERM_LUA = CONFIG_DIR . '/wezterm.lua';

// Set JSON content type for most responses
header('Content-Type: application/json');

/**
 * Sanitize certificate name - allow only alphanumeric, dash, underscore
 *
 * @param string $name Raw certificate name
 * @return string|false Sanitized name or false if invalid
 */
function sanitize_cert_name($name) {
    if (empty($name)) {
        return false;
    }

    // Remove any characters that aren't alphanumeric, dash, or underscore
    $sanitized = preg_replace('/[^a-zA-Z0-9_-]/', '', $name);

    // Ensure it's not empty after sanitization and not too long
    if (empty($sanitized) || strlen($sanitized) > 64) {
        return false;
    }

    return $sanitized;
}

/**
 * Validate IP address (IPv4 or IPv6)
 *
 * @param string $ip IP address to validate
 * @return bool True if valid
 */
function validate_ip_address($ip) {
    // Allow 0.0.0.0 for binding to all interfaces
    if ($ip === '0.0.0.0') {
        return true;
    }

    return filter_var($ip, FILTER_VALIDATE_IP) !== false;
}

/**
 * Validate port number
 *
 * @param mixed $port Port number to validate
 * @return bool True if valid
 */
function validate_port($port) {
    if (!is_numeric($port)) {
        return false;
    }

    $port = intval($port);
    return $port >= 1 && $port <= 65535;
}

/**
 * Execute a shell script and return result
 *
 * @param string $script Script name (without path)
 * @param array $args Arguments to pass to script
 * @return array ['success' => bool, 'output' => string, 'code' => int]
 */
function exec_script($script, $args = []) {
    $script_path = SCRIPTS_DIR . '/' . $script;

    // Security: Verify script exists and is in the scripts directory
    if (!file_exists($script_path)) {
        return [
            'success' => false,
            'output' => "Script not found: $script",
            'code' => 1
        ];
    }

    // Build command with escaped arguments
    $cmd_parts = [escapeshellcmd($script_path)];
    foreach ($args as $arg) {
        $cmd_parts[] = escapeshellarg($arg);
    }
    $cmd = implode(' ', $cmd_parts);

    // Execute and capture output
    exec($cmd . ' 2>&1', $output, $return_code);

    return [
        'success' => $return_code === 0,
        'output' => implode("\n", $output),
        'code' => $return_code
    ];
}

/**
 * Return JSON response and exit
 *
 * @param array $data Data to encode as JSON
 * @param int $status_code HTTP status code
 */
function json_response($data, $status_code = 200) {
    http_response_code($status_code);
    echo json_encode($data);
    exit;
}

/**
 * Return error JSON response and exit
 *
 * @param string $message Error message
 * @param int $status_code HTTP status code
 */
function json_error($message, $status_code = 400) {
    json_response([
        'success' => false,
        'message' => $message
    ], $status_code);
}

// Get action from POST or GET
$action = $_POST['action'] ?? $_GET['action'] ?? '';

// Handle actions
switch ($action) {

    // ========================================================================
    // Service Control Actions
    // ========================================================================

    case 'start':
        $result = exec_script('service.sh', ['start']);
        json_response([
            'success' => $result['success'],
            'message' => $result['success']
                ? 'WezTerm server started successfully'
                : 'Failed to start WezTerm server: ' . $result['output']
        ]);
        break;

    case 'stop':
        $result = exec_script('service.sh', ['stop']);
        json_response([
            'success' => $result['success'],
            'message' => $result['success']
                ? 'WezTerm server stopped successfully'
                : 'Failed to stop WezTerm server: ' . $result['output']
        ]);
        break;

    case 'restart':
        $result = exec_script('service.sh', ['restart']);
        json_response([
            'success' => $result['success'],
            'message' => $result['success']
                ? 'WezTerm server restarted successfully'
                : 'Failed to restart WezTerm server: ' . $result['output']
        ]);
        break;

    // ========================================================================
    // Status Query
    // ========================================================================

    case 'status':
        // Get service status
        $status_result = exec_script('service.sh', ['status']);

        // Parse status output (expecting JSON from service.sh)
        if ($status_result['success']) {
            $status_data = json_decode($status_result['output'], true);
            if (json_last_error() === JSON_ERROR_NONE) {
                json_response($status_data);
            }
        }

        // Fallback if service.sh doesn't return JSON
        $running = false;
        $pid = null;

        // Check if process is running
        exec('pgrep -f "wezterm-mux-server" 2>/dev/null', $pid_output, $pid_code);
        if ($pid_code === 0 && !empty($pid_output)) {
            $running = true;
            $pid = intval($pid_output[0]);
        }

        // Get version
        exec('wezterm-mux-server --version 2>/dev/null', $ver_output);
        $version = !empty($ver_output) ? trim($ver_output[0]) : 'Unknown';

        // Get config
        $config = wezterm_read_config();

        json_response([
            'running' => $running,
            'pid' => $pid,
            'version' => $version,
            'address' => $config['LISTEN_ADDRESS'] ?? '0.0.0.0',
            'port' => $config['LISTEN_PORT'] ?? '8080'
        ]);
        break;

    // ========================================================================
    // Certificate Management
    // ========================================================================

    case 'init_ca':
        // Initialize certificate authority
        if (!file_exists(CERTS_DIR)) {
            mkdir(CERTS_DIR, 0700, true);
        }

        $result = exec_script('cert-manager.sh', ['init']);
        json_response([
            'success' => $result['success'],
            'message' => $result['success']
                ? 'Certificate Authority initialized successfully'
                : 'Failed to initialize CA: ' . $result['output']
        ]);
        break;

    case 'generate_cert':
        // Generate new client certificate
        $name = $_POST['name'] ?? '';
        $sanitized_name = sanitize_cert_name($name);

        if (!$sanitized_name) {
            json_error('Invalid certificate name. Use only letters, numbers, dash, and underscore.');
        }

        // Check if CA exists
        if (!file_exists(CERTS_DIR . '/ca.crt')) {
            json_error('Certificate Authority not initialized. Please initialize CA first.', 400);
        }

        // Generate certificate
        $result = exec_script('cert-manager.sh', ['generate', $sanitized_name]);
        json_response([
            'success' => $result['success'],
            'message' => $result['success']
                ? "Client certificate '$sanitized_name' generated successfully"
                : 'Failed to generate certificate: ' . $result['output']
        ]);
        break;

    case 'revoke_cert':
        // Revoke a client certificate
        $name = $_POST['name'] ?? '';
        $sanitized_name = sanitize_cert_name($name);

        if (!$sanitized_name) {
            json_error('Invalid certificate name.');
        }

        $result = exec_script('cert-manager.sh', ['revoke', $sanitized_name]);
        json_response([
            'success' => $result['success'],
            'message' => $result['success']
                ? "Client certificate '$sanitized_name' revoked successfully"
                : 'Failed to revoke certificate: ' . $result['output']
        ]);
        break;

    case 'download_cert':
        // Download certificate bundle as ZIP
        $name = $_GET['name'] ?? '';
        $sanitized_name = sanitize_cert_name($name);

        if (!$sanitized_name) {
            json_error('Invalid certificate name.');
        }

        // Generate bundle
        $result = exec_script('cert-manager.sh', ['bundle', $sanitized_name]);

        if (!$result['success']) {
            json_error('Failed to create certificate bundle: ' . $result['output']);
        }

        // Bundle should be created at a temporary location
        // Extract path from output (assuming script outputs path)
        $bundle_path = trim($result['output']);

        // Default bundle path if script doesn't return path
        if (!file_exists($bundle_path)) {
            $bundle_path = '/tmp/wezterm-cert-' . $sanitized_name . '.zip';
        }

        if (!file_exists($bundle_path)) {
            json_error('Certificate bundle file not found.');
        }

        // Send file as download
        header('Content-Type: application/zip');
        header('Content-Disposition: attachment; filename="wezterm-' . $sanitized_name . '.zip"');
        header('Content-Length: ' . filesize($bundle_path));
        header('Cache-Control: no-cache');

        readfile($bundle_path);

        // Clean up temporary bundle
        unlink($bundle_path);
        exit;
        break;

    case 'list_certs':
        // List all issued certificates
        $certs = wezterm_list_certs();
        json_response([
            'success' => true,
            'certificates' => $certs
        ]);
        break;

    // ========================================================================
    // Configuration Management
    // ========================================================================

    case 'save_config':
        // Save configuration changes
        $address = $_POST['address'] ?? '';
        $port = $_POST['port'] ?? '';
        $log_level = $_POST['log_level'] ?? 'info';
        $service = $_POST['service'] ?? 'disable';

        // Validate inputs
        if (!validate_ip_address($address)) {
            json_error('Invalid IP address format.');
        }

        if (!validate_port($port)) {
            json_error('Invalid port number. Must be between 1 and 65535.');
        }

        // Validate log level
        $valid_log_levels = ['error', 'warn', 'info', 'debug', 'trace'];
        if (!in_array($log_level, $valid_log_levels)) {
            json_error('Invalid log level.');
        }

        // Validate service setting
        if (!in_array($service, ['enable', 'disable'])) {
            json_error('Invalid service setting. Must be enable or disable.');
        }

        // Read existing config
        $config = wezterm_read_config();

        // Update values
        $config['LISTEN_ADDRESS'] = $address;
        $config['LISTEN_PORT'] = $port;
        $config['LOG_LEVEL'] = $log_level;
        $config['SERVICE'] = $service;

        // Save config
        if (!wezterm_write_config($config)) {
            json_error('Failed to save configuration file.', 500);
        }

        // Regenerate wezterm.lua configuration
        if (!wezterm_generate_lua_config($config)) {
            json_error('Configuration saved but failed to generate wezterm.lua', 500);
        }

        // If service was enabled/disabled, update rc script
        if ($service === 'enable') {
            exec_script('service.sh', ['enable']);
        } else {
            exec_script('service.sh', ['disable']);
        }

        json_response([
            'success' => true,
            'message' => 'Configuration saved successfully. Restart the service for changes to take effect.'
        ]);
        break;

    case 'get_config':
        // Get current configuration
        $config = wezterm_read_config();
        json_response([
            'success' => true,
            'config' => $config
        ]);
        break;

    // ========================================================================
    // Installation Management
    // ========================================================================

    case 'install':
        // Install or update WezTerm binary
        $version = $_POST['version'] ?? 'latest';

        // Sanitize version
        if ($version !== 'latest' && !preg_match('/^\d+\.\d+\.\d+$/', $version)) {
            json_error('Invalid version format. Use "latest" or semver (e.g., "20240203-110809-5046fc22").');
        }

        $result = exec_script('install.sh', [$version]);
        json_response([
            'success' => $result['success'],
            'message' => $result['success']
                ? 'WezTerm installed successfully'
                : 'Failed to install WezTerm: ' . $result['output']
        ]);
        break;

    // ========================================================================
    // Logs
    // ========================================================================

    case 'get_logs':
        // Get recent log entries
        $lines = intval($_GET['lines'] ?? 100);
        $lines = min(max($lines, 10), 1000); // Clamp between 10 and 1000

        $log_file = '/var/log/wezterm-mux-server.log';

        if (!file_exists($log_file)) {
            json_response([
                'success' => true,
                'logs' => 'No log file found. Service may not have been started yet.'
            ]);
        }

        exec("tail -n $lines " . escapeshellarg($log_file) . " 2>&1", $log_output);

        json_response([
            'success' => true,
            'logs' => implode("\n", $log_output)
        ]);
        break;

    // ========================================================================
    // Default - Unknown Action
    // ========================================================================

    default:
        json_error('Unknown action: ' . htmlspecialchars($action), 400);
        break;
}

// Should never reach here due to exit calls in responses
json_error('Invalid request', 400);
