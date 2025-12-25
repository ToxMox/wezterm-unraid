#!/bin/bash
# Build script to create the .txz package for Unraid plugin

set -e

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERSION="2025.12.24o"
PACKAGE_NAME="wezterm-${VERSION}"
SOURCE_DIR="${SCRIPT_DIR}/archive/usr"
BUILD_DIR="${SCRIPT_DIR}/build"
OUTPUT_FILE="${SCRIPT_DIR}/archive/${PACKAGE_NAME}.txz"

echo "Building $PACKAGE_NAME.txz..."

# Clean up any previous build
rm -rf "$BUILD_DIR"
rm -f "$OUTPUT_FILE"

# Create build directory structure
mkdir -p "$BUILD_DIR/usr/local/emhttp/plugins/wezterm/include"
mkdir -p "$BUILD_DIR/usr/local/emhttp/plugins/wezterm/scripts"
mkdir -p "$BUILD_DIR/usr/local/emhttp/plugins/wezterm/images"
mkdir -p "$BUILD_DIR/install"

# Copy plugin files
cp "${SOURCE_DIR}/local/emhttp/plugins/wezterm/wezterm.page" "$BUILD_DIR/usr/local/emhttp/plugins/wezterm/"
cp "${SOURCE_DIR}/local/emhttp/plugins/wezterm/include/"*.php "$BUILD_DIR/usr/local/emhttp/plugins/wezterm/include/"
cp "${SOURCE_DIR}/local/emhttp/plugins/wezterm/scripts/"* "$BUILD_DIR/usr/local/emhttp/plugins/wezterm/scripts/"

# Make scripts executable
chmod +x "$BUILD_DIR/usr/local/emhttp/plugins/wezterm/scripts/"*

# Create slack-desc (Slackware package description)
cat > "$BUILD_DIR/install/slack-desc" << 'SLACKDESC'
       |-----handy-ruler------------------------------------------------------|
wezterm: WezTerm Server (Terminal multiplexer for Unraid)
wezterm:
wezterm: WezTerm mux-server provides persistent, multiplexed terminal
wezterm: sessions accessible from WezTerm clients via TLS authentication.
wezterm:
wezterm: Features:
wezterm: - Persistent terminal sessions that survive disconnection
wezterm: - TLS client certificate authentication
wezterm: - Web UI for configuration and certificate management
wezterm:
wezterm: Homepage: https://wezfurlong.org/wezterm/
wezterm:
SLACKDESC

# Create the package with root ownership
cd "$BUILD_DIR"
tar --owner=root --group=root -cvf - . | xz -9 > "$OUTPUT_FILE"

# Cleanup build directory
rm -rf "$BUILD_DIR"

echo ""
echo "Package created: $OUTPUT_FILE"
echo ""
md5sum "$OUTPUT_FILE"
