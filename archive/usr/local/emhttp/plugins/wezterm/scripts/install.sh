#!/bin/bash

set -e

PLUGIN_DIR="/boot/config/plugins/wezterm"
CONFIG_FILE="$PLUGIN_DIR/wezterm.cfg"
VERSION_FILE="$PLUGIN_DIR/version.txt"

# Source configuration
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

WEZTERM_VERSION="${VERSION:-latest}"

install_wezterm() {
  echo "Installing WezTerm version: $WEZTERM_VERSION"

  # Determine download URL - get latest release tag from GitHub API
  if [ "$WEZTERM_VERSION" = "latest" ]; then
    LATEST_TAG=$(curl -sI https://github.com/wezterm/wezterm/releases/latest | grep -i "^location:" | sed 's/.*tag\///' | tr -d '\r\n')
    if [ -z "$LATEST_TAG" ]; then
      echo "Failed to get latest version tag"
      exit 1
    fi
    DOWNLOAD_URL="https://github.com/wezterm/wezterm/releases/download/${LATEST_TAG}/WezTerm-${LATEST_TAG}-Ubuntu20.04.AppImage"
  else
    DOWNLOAD_URL="https://github.com/wezterm/wezterm/releases/download/$WEZTERM_VERSION/WezTerm-$WEZTERM_VERSION-Ubuntu20.04.AppImage"
  fi

  TEMP_DIR="/tmp/wezterm-install-$$"
  mkdir -p "$TEMP_DIR"
  cd "$TEMP_DIR"

  echo "Downloading WezTerm AppImage..."
  if ! curl -L -o WezTerm.AppImage "$DOWNLOAD_URL"; then
    echo "Failed to download WezTerm"
    rm -rf "$TEMP_DIR"
    exit 1
  fi

  chmod +x WezTerm.AppImage

  echo "Extracting AppImage..."
  ./WezTerm.AppImage --appimage-extract

  echo "Installing wezterm binaries..."
  cp squashfs-root/usr/bin/wezterm-mux-server /usr/local/bin/
  cp squashfs-root/usr/bin/wezterm /usr/local/bin/
  chmod +x /usr/local/bin/wezterm-mux-server
  chmod +x /usr/local/bin/wezterm

  # Install bundled libraries (Unraid 7 uses OpenSSL 3, but WezTerm needs OpenSSL 1.1)
  echo "Installing bundled libraries..."
  mkdir -p /usr/local/lib/wezterm
  cp squashfs-root/usr/lib/libssl.so.1.1 /usr/local/lib/wezterm/
  cp squashfs-root/usr/lib/libcrypto.so.1.1 /usr/local/lib/wezterm/

  # Get version info
  VERSION_INFO=$(LD_LIBRARY_PATH=/usr/local/lib/wezterm /usr/local/bin/wezterm-mux-server --version | head -1)
  echo "$VERSION_INFO" > "$VERSION_FILE"

  echo "Cleaning up..."
  cd /
  rm -rf "$TEMP_DIR"

  echo "WezTerm installed successfully: $VERSION_INFO"

  # Generate wezterm.lua configuration
  update_config
}

update_config() {
  echo "Updating wezterm.lua configuration..."

  # Source current config
  if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
  fi

  LISTEN_ADDRESS="${LISTEN_ADDRESS:-0.0.0.0}"
  LISTEN_PORT="${LISTEN_PORT:-8080}"

  cat > "$PLUGIN_DIR/wezterm.lua" << LUACFG
local wezterm = require 'wezterm'
local config = {}

config.tls_servers = {
  {
    bind_address = '${LISTEN_ADDRESS}:${LISTEN_PORT}',
  },
}

return config
LUACFG

  echo "Configuration updated"
}

case "$1" in
  update-config)
    update_config
    ;;
  *)
    install_wezterm
    ;;
esac
