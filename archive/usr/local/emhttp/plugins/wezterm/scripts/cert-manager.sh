#!/bin/bash

set -e

WEZTERM_PKI_DIR="/root/.local/share/wezterm/pki"
CERTS_DIR="/boot/config/plugins/wezterm/certs"
CLIENTS_DIR="$CERTS_DIR/clients"

check_server_running() {
  if ! pgrep -f wezterm-mux-server >/dev/null; then
    echo "Error: WezTerm server is not running. Start it first to generate PKI."
    exit 1
  fi

  if [ ! -f "$WEZTERM_PKI_DIR/ca.pem" ]; then
    echo "Error: WezTerm PKI not found. Make sure the server is running with TLS enabled."
    exit 1
  fi
}

init_ca() {
  echo "WezTerm uses auto-generated PKI when the server starts."
  echo "Start the WezTerm server to initialize certificates."
  echo ""
  echo "Once running, use 'generate <name>' to create client certificates."
}

generate_client_cert() {
  local CLIENT_NAME="$1"

  if [ -z "$CLIENT_NAME" ]; then
    echo "Error: Client name required"
    exit 1
  fi

  check_server_running

  if [ -f "$CLIENTS_DIR/$CLIENT_NAME.pem" ]; then
    echo "Error: Certificate for $CLIENT_NAME already exists"
    exit 1
  fi

  echo "Generating client certificate for: $CLIENT_NAME"

  mkdir -p "$CLIENTS_DIR"

  # Use wezterm cli to generate client credentials (--pem outputs in PEM format)
  LD_LIBRARY_PATH=/usr/local/lib/wezterm /usr/local/bin/wezterm -n cli tlscreds --pem > "$CLIENTS_DIR/$CLIENT_NAME.pem"
  chmod 600 "$CLIENTS_DIR/$CLIENT_NAME.pem"

  echo "Client certificate generated successfully"
  echo "Credentials: $CLIENTS_DIR/$CLIENT_NAME.pem"
}

revoke_client_cert() {
  local CLIENT_NAME="$1"

  if [ -z "$CLIENT_NAME" ]; then
    echo "Error: Client name required"
    exit 1
  fi

  if [ ! -f "$CLIENTS_DIR/$CLIENT_NAME.pem" ]; then
    echo "Error: Certificate for $CLIENT_NAME not found"
    exit 1
  fi

  echo "Revoking certificate for: $CLIENT_NAME"

  mkdir -p "$CLIENTS_DIR/revoked"
  mv "$CLIENTS_DIR/$CLIENT_NAME.pem" "$CLIENTS_DIR/revoked/"

  echo "Certificate revoked successfully"
}

create_bundle() {
  local CLIENT_NAME="$1"
  local BUNDLE_FILE="$2"

  if [ -z "$CLIENT_NAME" ] || [ -z "$BUNDLE_FILE" ]; then
    echo "Error: Client name and bundle file required"
    exit 1
  fi

  check_server_running

  if [ ! -f "$CLIENTS_DIR/$CLIENT_NAME.pem" ]; then
    echo "Error: Certificate for $CLIENT_NAME not found"
    exit 1
  fi

  TEMP_DIR="/tmp/wezterm-bundle-$$"
  mkdir -p "$TEMP_DIR"

  # Copy the combined PEM file (contains private key and certificate)
  cp "$CLIENTS_DIR/$CLIENT_NAME.pem" "$TEMP_DIR/client.pem"

  # Copy CA from wezterm's PKI
  cp "$WEZTERM_PKI_DIR/ca.pem" "$TEMP_DIR/"

  # Get server hostname/IP for config
  HOSTNAME=$(hostname)

  # Source config for port
  source /boot/config/plugins/wezterm/wezterm.cfg 2>/dev/null || true
  PORT="${LISTEN_PORT:-8080}"

  # Create example client config
  cat > "$TEMP_DIR/wezterm-client.lua" << CLIENTCFG
-- Add this to your ~/.wezterm.lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.tls_clients = {
  {
    name = 'unraid',
    remote_address = '$HOSTNAME:$PORT',  -- Update with your Unraid IP/hostname
    pem_private_key = '/path/to/client.pem',
    pem_cert = '/path/to/client.pem',
    pem_ca = '/path/to/ca.pem',
  },
}

return config
CLIENTCFG

  # Create README
  cat > "$TEMP_DIR/README.txt" << READMECFG
WezTerm Client Certificate Bundle
==================================

This bundle contains:
- ca.pem: Certificate Authority certificate
- client.pem: Your client certificate and private key (KEEP SECRET!)
- wezterm-client.lua: Example configuration

Installation:
1. Copy ca.pem and client.pem to a secure location
   Example: ~/.config/wezterm/certs/

2. Update the paths in wezterm-client.lua to match your file locations

3. Add the tls_clients configuration to your ~/.wezterm.lua file

4. Update the remote_address with your Unraid server's IP or hostname

5. Connect with: wezterm connect unraid

Security Note:
- Keep client.pem private - anyone with this file can connect as you

For more information: https://wezterm.org/multiplexing.html
READMECFG

  # Create zip bundle
  cd "$TEMP_DIR"
  zip -r "$BUNDLE_FILE" ./*

  # Cleanup
  rm -rf "$TEMP_DIR"

  echo "Certificate bundle created: $BUNDLE_FILE"
}

list_certs() {
  echo "Client certificates:"
  if [ -d "$CLIENTS_DIR" ]; then
    found=0
    for cert in "$CLIENTS_DIR"/*.pem; do
      if [ -f "$cert" ]; then
        name=$(basename "$cert" .pem)
        echo "  - $name"
        found=1
      fi
    done
    if [ $found -eq 0 ]; then
      echo "  (none)"
    fi
  else
    echo "  (none)"
  fi
}

case "$1" in
  init)
    init_ca
    ;;
  generate)
    generate_client_cert "$2"
    ;;
  revoke)
    revoke_client_cert "$2"
    ;;
  bundle)
    create_bundle "$2" "$3"
    ;;
  list)
    list_certs
    ;;
  *)
    echo "Usage: $0 {init|generate <name>|revoke <name>|bundle <name> <output.zip>|list}"
    exit 1
    ;;
esac
