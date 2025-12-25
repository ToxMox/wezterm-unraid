<?php

define('WEZTERM_CONFIG_FILE', '/boot/config/plugins/wezterm/wezterm.cfg');
define('WEZTERM_CERTS_DIR', '/boot/config/plugins/wezterm/certs');
define('WEZTERM_CLIENTS_DIR', '/boot/config/plugins/wezterm/certs/clients');
define('WEZTERM_LUA_FILE', '/boot/config/plugins/wezterm/wezterm.lua');
define('WEZTERM_PID_FILE', '/var/run/wezterm/wezterm-mux-server.pid');

function wezterm_read_config() {
  $config = [
    'SERVICE' => 'disable',
    'LISTEN_ADDRESS' => '0.0.0.0',
    'LISTEN_PORT' => '8080',
    'LOG_LEVEL' => 'info',
    'VERSION' => 'latest'
  ];

  if (file_exists(WEZTERM_CONFIG_FILE)) {
    $lines = file(WEZTERM_CONFIG_FILE, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
      $line = trim($line);
      if (empty($line) || $line[0] === '#') continue;
      if (preg_match('/^([A-Z_]+)="([^"]*)"/', $line, $matches)) {
        $config[$matches[1]] = $matches[2];
      }
    }
  }

  return $config;
}

function wezterm_write_config($config) {
  $content = "# WezTerm Server Configuration\n";
  foreach ($config as $key => $value) {
    $content .= $key . '="' . $value . '"' . "\n";
  }
  return file_put_contents(WEZTERM_CONFIG_FILE, $content) !== false;
}

function wezterm_generate_lua_config($config) {
  $lua = <<<LUA
local wezterm = require 'wezterm'
local config = {}

config.tls_servers = {
  {
    bind_address = '{$config['LISTEN_ADDRESS']}:{$config['LISTEN_PORT']}',
  },
}

return config
LUA;
  return file_put_contents(WEZTERM_LUA_FILE, $lua) !== false;
}

function wezterm_get_status() {
  $running = false;
  $pid = null;

  if (file_exists(WEZTERM_PID_FILE)) {
    $pid = trim(file_get_contents(WEZTERM_PID_FILE));
    if ($pid && file_exists("/proc/$pid")) {
      $running = true;
    }
  }

  return [
    'running' => $running,
    'pid' => $pid
  ];
}

function wezterm_get_version() {
  $version_file = '/boot/config/plugins/wezterm/version.txt';
  if (file_exists($version_file)) {
    return trim(file_get_contents($version_file));
  }

  exec('wezterm-mux-server --version 2>&1', $output, $ret);
  if ($ret === 0 && !empty($output)) {
    return trim($output[0]);
  }

  return 'Not installed';
}

function wezterm_list_certs() {
  $certs = [];

  if (!is_dir(WEZTERM_CLIENTS_DIR)) {
    return $certs;
  }

  $files = glob(WEZTERM_CLIENTS_DIR . '/*.pem');
  foreach ($files as $cert_file) {
    $name = basename($cert_file, '.pem');
    $certs[] = [
      'name' => $name,
      'created' => date('Y-m-d', filemtime($cert_file)),
      'expires' => 'N/A'
    ];
  }

  return $certs;
}

function wezterm_get_cert_info($cert_file) {
  $info = [];

  exec('openssl x509 -in ' . escapeshellarg($cert_file) . ' -noout -dates 2>&1', $output, $ret);
  if ($ret === 0) {
    foreach ($output as $line) {
      if (preg_match('/notBefore=(.+)/', $line, $m)) {
        $info['created'] = date('Y-m-d', strtotime($m[1]));
      }
      if (preg_match('/notAfter=(.+)/', $line, $m)) {
        $info['expires'] = date('Y-m-d', strtotime($m[1]));
      }
    }
  }

  return $info;
}
