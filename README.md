# WezTerm Server for Unraid

A native Unraid 7+ plugin that runs `wezterm-mux-server` to provide persistent, multiplexed terminal sessions accessible from WezTerm clients using TLS certificate authentication.

## Overview

This plugin enables you to:
- Run persistent terminal sessions on your Unraid server
- Connect from any WezTerm client on your network
- Maintain sessions across disconnects and reconnects
- Access your server via secure TLS connections
- Manage multiple client certificates for different devices

## Requirements

- Unraid 7.0 or later
- WezTerm terminal emulator installed on client machines ([download here](https://wezfurlong.org/wezterm/installation.html))
- Network access to your Unraid server on the configured port (default: 8080)

## Installation

1. Add the plugin repository to Unraid Community Applications (if available)
2. Search for "WezTerm Server" and install
3. Alternatively, install manually by downloading the `.plg` file and placing it in `/boot/config/plugins/`

The plugin will automatically:
- Download and install the WezTerm server binary
- Create necessary directories
- Set up the configuration structure

## Initial Setup

### 1. Navigate to Settings

Go to **Settings > WezTerm Server** in your Unraid web interface.

### 2. Initialize Certificate Authority

Click the **Initialize CA** button to create the certificate authority needed for TLS authentication. This is a one-time operation that generates:
- A Certificate Authority (CA) for signing certificates
- A server certificate for the WezTerm server

### 3. Configure Service (Optional)

Adjust settings if needed:
- **Listen Address**: Default is `0.0.0.0` (all interfaces)
- **Listen Port**: Default is `8080` (change if there's a port conflict)
- **Log Level**: Set to `info` for normal operation

### 4. Start the Service

Click **Start** to launch the WezTerm server. Optionally, enable **Start on boot** to have the service start automatically when Unraid boots.

## Generating Client Certificates

Each device that will connect to the WezTerm server needs its own client certificate.

### Steps:

1. In the **Certificate Management** section, enter a descriptive name for the client (e.g., "laptop", "desktop", "work-machine")
2. Click **Generate**
3. Click **Download** next to the newly created certificate
4. Save the ZIP file to your client machine

The downloaded bundle contains:
- `ca.crt` - Certificate Authority certificate
- `client.crt` - Client certificate
- `client.key` - Client private key
- `wezterm-client.lua` - Example configuration snippet

## Client Configuration

### 1. Extract Certificate Bundle

Extract the downloaded ZIP file to a secure location on your client machine:

- **Linux/macOS**: `~/.config/wezterm/certs/unraid/`
- **Windows**: `%USERPROFILE%\.config\wezterm\certs\unraid\`

### 2. Update WezTerm Configuration

Add the following to your `~/.wezterm.lua` file (create it if it doesn't exist):

```lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- TLS connection to Unraid
config.tls_clients = {
  {
    name = "unraid",
    remote_address = "unraid.local:8080",  -- Change to your server's IP or hostname
    bootstrap_via_ssh = false,
    pem_private_key = wezterm.home_dir .. "/.config/wezterm/certs/unraid/client.key",
    pem_cert = wezterm.home_dir .. "/.config/wezterm/certs/unraid/client.crt",
    pem_ca = wezterm.home_dir .. "/.config/wezterm/certs/unraid/ca.crt",
  },
}

return config
```

#### Path Examples by Platform:

**Linux/macOS:**
```lua
pem_private_key = wezterm.home_dir .. "/.config/wezterm/certs/unraid/client.key",
pem_cert = wezterm.home_dir .. "/.config/wezterm/certs/unraid/client.crt",
pem_ca = wezterm.home_dir .. "/.config/wezterm/certs/unraid/ca.crt",
```

**Windows:**
```lua
pem_private_key = wezterm.home_dir .. "\\.config\\wezterm\\certs\\unraid\\client.key",
pem_cert = wezterm.home_dir .. "\\.config\\wezterm\\certs\\unraid\\client.crt",
pem_ca = wezterm.home_dir .. "\\.config\\wezterm\\certs\\unraid\\ca.crt",
```

### 3. Verify Remote Address

Replace `unraid.local:8080` with your actual server address:
- IP address: `192.168.1.100:8080`
- Hostname: `tower.local:8080`
- Custom port: `unraid.local:9000` (if you changed the default)

## Connecting

Once configured, connect to your Unraid server using:

```bash
wezterm connect unraid
```

Your terminal session will run on the Unraid server. You can:
- Disconnect and reconnect without losing your session
- Run long-running processes that persist
- Use tmux or other terminal multiplexers within the session

To disconnect, simply close the window or press `Ctrl+D`. Your session remains active on the server.

## Troubleshooting

### Connection Refused

**Symptoms:** `connection refused` error when running `wezterm connect`

**Solutions:**
- Verify the WezTerm Server service is running in Unraid (Settings > WezTerm Server)
- Check that the port (default 8080) is not blocked by your firewall
- Confirm you're using the correct server address and port in your config
- Test connectivity: `telnet unraid.local 8080` or `nc -zv unraid.local 8080`

### Certificate Errors

**Symptoms:** TLS handshake errors, certificate validation failures

**Solutions:**
- Ensure all three certificate files (`ca.crt`, `client.crt`, `client.key`) are present
- Verify file paths in your `~/.wezterm.lua` are correct and use proper path separators
- Check file permissions (certificates should be readable by your user)
- Try regenerating the client certificate if it's corrupted
- If you regenerated the CA, you must regenerate all client certificates

### Service Won't Start

**Symptoms:** Service shows as stopped, or immediately stops after starting

**Solutions:**
- Check the WezTerm logs in Unraid (path shown in the Settings page)
- Verify no other service is using the configured port: `netstat -tlnp | grep 8080`
- Ensure certificates were initialized (CA and server certificates exist)
- Verify WezTerm binary is installed: `/usr/local/bin/wezterm-mux-server --version`

### Sessions Not Persisting

**Symptoms:** Sessions end when you disconnect

**Solutions:**
- Verify you're using `wezterm connect unraid`, not SSH
- Check that the WezTerm server service wasn't restarted (sessions reset on restart)
- Review server logs for session termination messages

## Security Considerations

### Certificate Security

- **Protect private keys**: The `client.key` file should never be shared. Store it with restricted permissions (chmod 600 on Linux/macOS)
- **One certificate per device**: Generate separate certificates for each client device
- **Revoke compromised certificates**: If a device is lost or compromised, revoke its certificate in the WezTerm Server settings

### Network Security

- **Firewall rules**: Consider restricting the WezTerm server port to your local network
- **VPN access**: For remote access, use a VPN instead of exposing the port to the internet
- **TLS only**: This plugin requires TLS; unencrypted connections are not supported

### Certificate Expiration

- **Client certificates**: Valid for 1 year by default
- **Server certificate**: Valid for 10 years
- **CA certificate**: Valid for 10 years

You'll need to regenerate client certificates annually. The plugin will show expiration warnings in the web interface.

## Uninstallation

To remove the WezTerm Server plugin:

1. Go to **Settings > WezTerm Server** and click **Stop** to shut down the service
2. Navigate to **Plugins** in the Unraid web interface
3. Find "WezTerm Server" and click **Remove**

The plugin will automatically:
- Stop the WezTerm server service
- Remove the binary from `/usr/local/bin/`
- Clean up runtime files

**Note:** Certificates and configuration stored in `/boot/config/plugins/wezterm/` are preserved. To completely remove all data, manually delete this directory:

```bash
rm -rf /boot/config/plugins/wezterm/
```

## Support

- **Issues**: Report bugs or request features via the plugin's GitHub repository
- **Documentation**: [WezTerm Multiplexing Guide](https://wezterm.org/multiplexing.html)
- **Community**: Unraid Forums

## License

This plugin is provided as-is under the MIT License. WezTerm is developed by Wez Furlong and licensed separately.
