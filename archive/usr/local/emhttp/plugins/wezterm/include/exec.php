<?php
require_once 'helpers.php';

header('Content-Type: application/json');

$action = $_REQUEST['action'] ?? '';

switch ($action) {
  case 'start':
    exec('/etc/rc.d/rc.wezterm start 2>&1', $output, $ret);
    echo json_encode(['success' => $ret === 0, 'message' => $ret === 0 ? 'Service started' : 'Failed to start: ' . implode("\n", $output)]);
    break;

  case 'stop':
    exec('/etc/rc.d/rc.wezterm stop 2>&1', $output, $ret);
    echo json_encode(['success' => $ret === 0, 'message' => $ret === 0 ? 'Service stopped' : 'Failed to stop: ' . implode("\n", $output)]);
    break;

  case 'restart':
    exec('/etc/rc.d/rc.wezterm restart 2>&1', $output, $ret);
    echo json_encode(['success' => $ret === 0, 'message' => $ret === 0 ? 'Service restarted' : 'Failed to restart: ' . implode("\n", $output)]);
    break;

  case 'status':
    $status = wezterm_get_status();
    echo json_encode($status);
    break;

  case 'set_autostart':
    $enabled = $_POST['enabled'] === '1';
    $config = wezterm_read_config();
    $config['SERVICE'] = $enabled ? 'enable' : 'disable';
    wezterm_write_config($config);

    // Update boot script
    if ($enabled) {
      exec('/usr/local/emhttp/plugins/wezterm/scripts/rc.wezterm enable 2>&1');
    } else {
      exec('/usr/local/emhttp/plugins/wezterm/scripts/rc.wezterm disable 2>&1');
    }

    echo json_encode(['success' => true, 'message' => 'Autostart ' . ($enabled ? 'enabled' : 'disabled')]);
    break;

  case 'save_config':
    $config = wezterm_read_config();
    $config['LISTEN_ADDRESS'] = $_POST['LISTEN_ADDRESS'] ?? '0.0.0.0';
    $config['LISTEN_PORT'] = $_POST['LISTEN_PORT'] ?? '8080';
    $config['LOG_LEVEL'] = $_POST['LOG_LEVEL'] ?? 'info';
    wezterm_write_config($config);
    wezterm_generate_lua_config($config);
    echo json_encode(['success' => true, 'message' => 'Configuration saved']);
    break;

  case 'init_ca':
    // PKI is auto-generated when server starts - just inform user
    echo json_encode(['success' => true, 'message' => 'PKI is auto-generated when the server starts. Start the server first, then generate client certificates.']);
    break;

  case 'generate_cert':
    $name = preg_replace('/[^a-zA-Z0-9_-]/', '', $_POST['cert_name'] ?? '');
    if (empty($name)) {
      echo json_encode(['success' => false, 'message' => 'Invalid certificate name']);
      break;
    }
    exec('/usr/local/emhttp/plugins/wezterm/scripts/cert-manager.sh generate ' . escapeshellarg($name) . ' 2>&1', $output, $ret);
    echo json_encode(['success' => $ret === 0, 'message' => $ret === 0 ? 'Certificate generated for ' . $name : 'Failed: ' . implode("\n", $output)]);
    break;

  case 'revoke_cert':
    $name = preg_replace('/[^a-zA-Z0-9_-]/', '', $_GET['name'] ?? $_POST['name'] ?? '');
    if (empty($name)) {
      echo json_encode(['success' => false, 'message' => 'Invalid certificate name']);
      break;
    }
    exec('/usr/local/emhttp/plugins/wezterm/scripts/cert-manager.sh revoke ' . escapeshellarg($name) . ' 2>&1', $output, $ret);
    echo json_encode(['success' => $ret === 0, 'message' => $ret === 0 ? 'Certificate revoked' : 'Failed: ' . implode("\n", $output)]);
    break;

  case 'download_cert':
    $name = preg_replace('/[^a-zA-Z0-9_-]/', '', $_GET['name'] ?? '');
    if (empty($name)) {
      die('Invalid certificate name');
    }

    $bundle = '/tmp/wezterm-cert-' . $name . '.zip';
    exec('/usr/local/emhttp/plugins/wezterm/scripts/cert-manager.sh bundle ' . escapeshellarg($name) . ' ' . escapeshellarg($bundle) . ' 2>&1', $output, $ret);

    if ($ret === 0 && file_exists($bundle)) {
      header('Content-Type: application/zip');
      header('Content-Disposition: attachment; filename="wezterm-' . $name . '.zip"');
      readfile($bundle);
      unlink($bundle);
      exit;
    } else {
      die('Failed to create certificate bundle');
    }
    break;

  default:
    echo json_encode(['success' => false, 'message' => 'Unknown action']);
}
