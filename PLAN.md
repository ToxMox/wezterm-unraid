# WezTerm Server Plugin for Unraid 7+ - Implementation Plan

## Overview

Build a native Unraid 7+ plugin that runs `wezterm-mux-server` for persistent, multiplexed terminal sessions accessible from WezTerm clients via TLS authentication.

## Project Structure

```
wezterm-unraid/
├── wezterm.plg                           # Main plugin file
├── src/
│   └── usr/local/emhttp/plugins/wezterm/
│       ├── wezterm.page                  # Settings UI
│       ├── include/
│       │   ├── exec.php                  # AJAX action handler
│       │   └── helpers.php               # Shared PHP functions
│       ├── scripts/
│       │   ├── install.sh                # Download/install WezTerm
│       │   ├── cert-manager.sh           # Certificate generation
│       │   └── service.sh                # Start/stop/status
│       └── images/
│           └── wezterm.png               # Plugin icon
├── README.md
└── PLAN.md
```

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Binary distribution | AppImage extraction | Self-contained, no dependency issues on Slackware-based Unraid |
| Certificate storage | `/boot/config/plugins/wezterm/certs/` | Persists across reboots |
| Config storage | `/boot/config/plugins/wezterm/wezterm.cfg` | Standard Unraid pattern |
| Runtime directory | `/var/run/wezterm/` | Ephemeral, recreated on boot |
| Service management | rc.d script | Standard Unraid pattern |

---

## Implementation Tasks

### Phase 1: Core Plugin Infrastructure

#### Task 1.1: Create Plugin Manifest (.plg file)
**File:** `wezterm.plg`

Create the XML plugin manifest with:
- Entity declarations (name, version, author, paths, URLs)
- Minimum Unraid version requirement (`min="7.0.0"`)
- Plugin metadata (icon, support URL, launch path)
- FILE sections for:
  - Creating directory structure
  - Extracting web UI files to `/usr/local/emhttp/plugins/wezterm/`
  - Creating default config if not exists
  - Installing rc.d service script
  - Running post-install setup
- Removal script to clean up

**Acceptance criteria:**
- Plugin installs cleanly on Unraid 7.2.2
- Plugin appears in Settings menu
- Plugin uninstalls cleanly

---

#### Task 1.2: Create Settings Page UI
**File:** `src/usr/local/emhttp/plugins/wezterm/wezterm.page`

Create the main settings interface with:
- Header: `Menu="Settings" Icon="terminal" Title="WezTerm Server"`
- Status section showing:
  - Service status (Running/Stopped)
  - WezTerm version installed
  - Listening address:port
  - Number of client certificates issued
- Service controls:
  - Start/Stop/Restart buttons
  - "Start on boot" toggle
- Configuration section:
  - Listen address (default: `0.0.0.0`)
  - Listen port (default: `8080`)
  - Log level dropdown
- Certificate management section:
  - "Initialize CA" button (first-time setup)
  - Table of issued client certificates (name, created date, actions)
  - "Generate New Client Certificate" form
  - Download/Revoke buttons per certificate

**Acceptance criteria:**
- Page renders correctly in Unraid GUI
- All form elements functional
- Responsive layout

---

#### Task 1.3: Create AJAX Handler
**File:** `src/usr/local/emhttp/plugins/wezterm/include/exec.php`

Handle actions:
- `start` - Start wezterm-mux-server
- `stop` - Stop service
- `restart` - Restart service
- `status` - Return JSON status
- `init_ca` - Initialize certificate authority
- `generate_cert` - Generate new client certificate
- `revoke_cert` - Revoke a client certificate
- `download_cert` - Return certificate bundle as zip
- `save_config` - Save configuration changes

**Acceptance criteria:**
- All actions return appropriate JSON responses
- Error handling with meaningful messages
- Input validation/sanitization

---

#### Task 1.4: Create Helper Functions
**File:** `src/usr/local/emhttp/plugins/wezterm/include/helpers.php`

Functions:
- `wezterm_read_config()` - Parse cfg file
- `wezterm_write_config()` - Save cfg file
- `wezterm_get_status()` - Check if service running
- `wezterm_get_version()` - Get installed version
- `wezterm_list_certs()` - List issued certificates
- `wezterm_get_cert_info()` - Get certificate details

**Acceptance criteria:**
- All functions tested and working
- Proper error handling

---

### Phase 2: WezTerm Binary Management

#### Task 2.1: Create Installation Script
**File:** `src/usr/local/emhttp/plugins/wezterm/scripts/install.sh`

Script functionality:
- Check for existing installation
- Download latest WezTerm AppImage from GitHub releases
- Verify SHA256 checksum
- Extract AppImage contents
- Copy `wezterm-mux-server` binary to `/usr/local/bin/`
- Set proper permissions
- Store version info

**Key considerations:**
- AppImage contains `wezterm-mux-server` at `squashfs-root/usr/bin/wezterm-mux-server`
- Need `--appimage-extract` to extract
- Handle network failures gracefully
- Support version pinning or "latest"

**Acceptance criteria:**
- Script downloads and extracts WezTerm successfully
- `wezterm-mux-server --version` works after install
- Idempotent (can run multiple times safely)

---

#### Task 2.2: Create Service Management Script
**File:** `src/usr/local/emhttp/plugins/wezterm/scripts/service.sh` (also symlinked to `/etc/rc.d/rc.wezterm`)

Script functionality:
- `start` - Launch wezterm-mux-server with configured options
- `stop` - Graceful shutdown
- `restart` - Stop then start
- `status` - Check if running, return JSON
- `enable` - Add to go script for boot start
- `disable` - Remove from go script

**wezterm-mux-server launch options:**
```bash
wezterm-mux-server \
  --daemonize \
  --config-file /boot/config/plugins/wezterm/wezterm.lua
```

**Acceptance criteria:**
- Service starts and runs in background
- Service stops cleanly
- PID file management works
- Status returns accurate information

---

### Phase 3: Certificate Management

#### Task 3.1: Create Certificate Manager Script
**File:** `src/usr/local/emhttp/plugins/wezterm/scripts/cert-manager.sh`

Commands:
- `init` - Initialize CA (generate CA key + cert)
- `generate <name>` - Generate client certificate signed by CA
- `revoke <name>` - Revoke a certificate (add to CRL)
- `list` - List all certificates with status
- `bundle <name>` - Create downloadable zip with:
  - `ca.crt` - CA certificate
  - `client.crt` - Client certificate
  - `client.key` - Client private key
  - `wezterm-client.lua` - Example client config snippet

**Certificate paths:**
```
/boot/config/plugins/wezterm/certs/
├── ca.key              # CA private key (never leaves server)
├── ca.crt              # CA certificate (distributed to clients)
├── server.key          # Server private key
├── server.crt          # Server certificate
└── clients/
    ├── laptop.key
    ├── laptop.crt
    ├── desktop.key
    └── desktop.crt
```

**Certificate generation using OpenSSL:**
```bash
# CA
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt -subj "/CN=WezTerm-Unraid-CA"

# Server
openssl genrsa -out server.key 4096
openssl req -new -key server.key -out server.csr -subj "/CN=$(hostname)"
openssl x509 -req -days 3650 -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt

# Client
openssl genrsa -out client.key 4096
openssl req -new -key client.key -out client.csr -subj "/CN=clientname"
openssl x509 -req -days 365 -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out client.crt
```

**Acceptance criteria:**
- CA initialization works
- Client certs can be generated with custom names
- Bundle download contains all needed files
- Example config in bundle is correct

---

#### Task 3.2: Create WezTerm Server Configuration
**File:** Template for `/boot/config/plugins/wezterm/wezterm.lua`

```lua
local wezterm = require 'wezterm'
local config = {}

config.tls_servers = {
  {
    bind_address = '0.0.0.0:8080',  -- From plugin config
    pem_private_key = '/boot/config/plugins/wezterm/certs/server.key',
    pem_cert = '/boot/config/plugins/wezterm/certs/server.crt',
    pem_ca = '/boot/config/plugins/wezterm/certs/ca.crt',
  },
}

return config
```

**Acceptance criteria:**
- Config regenerated when settings change
- Valid Lua syntax
- Correct paths to certificates

---

### Phase 4: Polish & Documentation

#### Task 4.1: Add Plugin Icon
**File:** `src/usr/local/emhttp/plugins/wezterm/images/wezterm.png`

- Use WezTerm logo or create derivative
- 48x48 PNG for Unraid GUI

---

#### Task 4.2: Create User Documentation
**File:** In-plugin help text and README.md

Document:
- Initial setup steps
- How to generate and install client certificates
- Example client configuration for various platforms
- Troubleshooting common issues
- Security considerations

---

#### Task 4.3: Test Complete Flow
End-to-end testing:
1. Install plugin on Unraid 7.2.2
2. Initialize CA
3. Configure port
4. Start service
5. Generate client certificate
6. Download certificate bundle
7. Configure WezTerm client on remote machine
8. Connect successfully with `wezterm connect unraid`
9. Verify session persistence (disconnect and reconnect)
10. Stop/start service
11. Uninstall plugin cleanly

---

## Configuration File Format

**File:** `/boot/config/plugins/wezterm/wezterm.cfg`

```ini
# WezTerm Server Configuration
SERVICE="disable"           # enable|disable (start on boot)
LISTEN_ADDRESS="0.0.0.0"    # Bind address
LISTEN_PORT="8080"          # Bind port
LOG_LEVEL="info"            # error|warn|info|debug|trace
VERSION="latest"            # WezTerm version to use
```

---

## Dependencies

- OpenSSL (included in Unraid)
- curl (included in Unraid)
- unzip/zip (included in Unraid)
- FUSE (for AppImage extraction) - verify availability

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| AppImage won't extract on Unraid | Fall back to building from source or use static binary if available |
| WezTerm updates break compatibility | Pin to known-working version, test updates before recommending |
| Certificate complexity confuses users | Provide one-click bundle download with working example config |
| Port conflicts | Allow configurable port, check for conflicts before starting |

---

## Future Enhancements (Out of Scope for v1)

- [ ] Web terminal fallback (ttyd integration)
- [ ] Automatic certificate renewal notifications
- [ ] Multiple server instances
- [ ] Integration with Unraid's user management
- [ ] Container support as alternative deployment

---

## References

- [WezTerm Multiplexing Docs](https://wezterm.org/multiplexing.html)
- [WezTerm TlsDomainClient](https://wezterm.org/config/lua/TlsDomainClient.html)
- [WezTerm GitHub Releases](https://github.com/wezterm/wezterm/releases)
- [Unraid Plugin Examples - nvidia-driver](https://github.com/ich777/unraid-nvidia-driver)
- [Unraid Plugin Examples - NerdPack](https://github.com/dmacias72/unRAID-plugins)
- [Unraid .page File Example](https://github.com/linuxserver-archive/Unraid-DVB-Plugin)
