#!/bin/bash
#
# WezTerm Installation Script for Unraid
# Downloads and installs WezTerm multiplexer server from GitHub releases
#

set -e  # Exit on error
set -u  # Exit on undefined variable

# Configuration
PLUGIN_DIR="/boot/config/plugins/wezterm"
INSTALL_DIR="/usr/local/bin"
TEMP_DIR="/tmp/wezterm-install-$$"
GITHUB_REPO="wez/wezterm"
DEFAULT_VERSION="20240203-110809-5046fc22"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Cleanup function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        log_info "Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
    fi
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()

    for cmd in curl sha256sum; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install them and try again."
        exit 1
    fi

    log_info "All dependencies satisfied."
}

# Get latest version from GitHub
get_latest_version() {
    log_info "Fetching latest version from GitHub..."

    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | \
        grep '"tag_name":' | \
        sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')

    if [ -z "$latest_version" ]; then
        log_warn "Could not fetch latest version from GitHub API, using default: $DEFAULT_VERSION"
        echo "$DEFAULT_VERSION"
    else
        echo "$latest_version"
    fi
}

# Check if version is already installed
check_existing_installation() {
    local version=$1

    if [ -f "$PLUGIN_DIR/version" ]; then
        local installed_version
        installed_version=$(cat "$PLUGIN_DIR/version")

        if [ "$installed_version" = "$version" ]; then
            log_info "WezTerm version $version is already installed."

            # Verify binary exists and works
            if [ -f "$INSTALL_DIR/wezterm-mux-server" ] && \
               "$INSTALL_DIR/wezterm-mux-server" --version &> /dev/null; then
                log_info "Installation verified. No action needed."
                return 0
            else
                log_warn "Binary missing or not working. Reinstalling..."
                return 1
            fi
        else
            log_info "Upgrading from version $installed_version to $version"
            return 1
        fi
    fi

    return 1
}

# Download AppImage
download_appimage() {
    local version=$1
    local appimage_url="https://github.com/${GITHUB_REPO}/releases/download/${version}/WezTerm-${version}-Ubuntu20.04.AppImage"
    local appimage_path="$TEMP_DIR/wezterm.AppImage"

    log_info "Downloading WezTerm AppImage version $version..."
    log_info "URL: $appimage_url"

    if ! curl -L -f -o "$appimage_path" "$appimage_url" --progress-bar; then
        log_error "Failed to download AppImage from $appimage_url"
        log_error "Please check if the version exists or your internet connection."
        exit 1
    fi

    log_info "Download completed successfully."
    echo "$appimage_path"
}

# Download and verify checksum
download_and_verify_checksum() {
    local version=$1
    local appimage_path=$2
    local checksum_url="https://github.com/${GITHUB_REPO}/releases/download/${version}/WezTerm-${version}-Ubuntu20.04.AppImage.sha256"
    local checksum_file="$TEMP_DIR/wezterm.AppImage.sha256"

    log_info "Downloading SHA256 checksum..."

    # Try to download checksum file
    if curl -L -f -s -o "$checksum_file" "$checksum_url" 2>/dev/null; then
        log_info "Verifying checksum..."

        # Extract just the hash value (handle different checksum file formats)
        local expected_hash
        expected_hash=$(cat "$checksum_file" | awk '{print $1}')

        # Calculate actual hash
        local actual_hash
        actual_hash=$(sha256sum "$appimage_path" | awk '{print $1}')

        if [ "$expected_hash" = "$actual_hash" ]; then
            log_info "Checksum verification passed."
            return 0
        else
            log_error "Checksum verification failed!"
            log_error "Expected: $expected_hash"
            log_error "Got: $actual_hash"
            exit 1
        fi
    else
        log_warn "Could not download checksum file. Skipping verification."
        log_warn "This is not recommended for production use."
    fi
}

# Extract AppImage
extract_appimage() {
    local appimage_path=$1

    log_info "Making AppImage executable..."
    chmod +x "$appimage_path"

    log_info "Extracting AppImage contents..."
    cd "$TEMP_DIR"

    if ! "$appimage_path" --appimage-extract &> /dev/null; then
        log_error "Failed to extract AppImage"
        exit 1
    fi

    if [ ! -d "$TEMP_DIR/squashfs-root" ]; then
        log_error "Extraction failed: squashfs-root directory not found"
        exit 1
    fi

    log_info "AppImage extracted successfully."
}

# Install binary and dependencies
install_binary() {
    local extract_dir="$TEMP_DIR/squashfs-root"
    local binary_source="$extract_dir/usr/bin/wezterm-mux-server"
    local binary_dest="$INSTALL_DIR/wezterm-mux-server"

    log_info "Installing WezTerm multiplexer server..."

    # Check if binary exists in extracted files
    if [ ! -f "$binary_source" ]; then
        log_error "Binary not found at expected location: $binary_source"
        log_error "Listing contents of extraction directory:"
        ls -la "$extract_dir/usr/bin/" || true
        exit 1
    fi

    # Create plugin directory if it doesn't exist
    mkdir -p "$PLUGIN_DIR"
    mkdir -p "$INSTALL_DIR"

    # Copy binary
    log_info "Copying binary to $binary_dest..."
    cp -f "$binary_source" "$binary_dest"

    # Set proper permissions
    chmod 755 "$binary_dest"

    # Check if we need to copy any shared libraries
    log_info "Checking for required libraries..."

    # Create lib directory for any necessary libraries
    local lib_dir="$PLUGIN_DIR/lib"
    mkdir -p "$lib_dir"

    # Copy any .so files that might be needed (if they exist)
    if [ -d "$extract_dir/usr/lib" ]; then
        log_info "Copying required libraries..."
        cp -rf "$extract_dir/usr/lib/"* "$lib_dir/" 2>/dev/null || true
    fi

    log_info "Binary installation completed."
}

# Verify installation
verify_installation() {
    local version=$1
    local binary_path="$INSTALL_DIR/wezterm-mux-server"

    log_info "Verifying installation..."

    if [ ! -f "$binary_path" ]; then
        log_error "Binary not found at $binary_path"
        exit 1
    fi

    if [ ! -x "$binary_path" ]; then
        log_error "Binary is not executable"
        exit 1
    fi

    # Test binary execution
    log_info "Testing binary execution..."
    if ! "$binary_path" --version &> /dev/null; then
        log_error "Binary test failed. The binary may be missing dependencies."
        log_error "Run 'ldd $binary_path' to check for missing libraries."
        exit 1
    fi

    # Get actual version from binary
    local binary_version
    binary_version=$("$binary_path" --version 2>&1 | head -n 1 || echo "unknown")
    log_info "Installed binary reports: $binary_version"

    log_info "Installation verification passed."
}

# Store version information
store_version() {
    local version=$1

    log_info "Storing version information..."
    echo "$version" > "$PLUGIN_DIR/version"
    echo "$(date)" > "$PLUGIN_DIR/install_date"

    log_info "Version information saved to $PLUGIN_DIR/version"
}

# Main installation function
main() {
    local version="${1:-}"

    echo "========================================="
    echo "WezTerm Installation Script for Unraid"
    echo "========================================="
    echo ""

    # Check dependencies
    check_dependencies

    # Determine version to install
    if [ -z "$version" ] || [ "$version" = "latest" ]; then
        version=$(get_latest_version)
    fi

    log_info "Target version: $version"

    # Check if already installed
    if check_existing_installation "$version"; then
        exit 0
    fi

    # Create temporary directory
    log_info "Creating temporary directory: $TEMP_DIR"
    mkdir -p "$TEMP_DIR"

    # Download AppImage
    local appimage_path
    appimage_path=$(download_appimage "$version")

    # Verify checksum
    download_and_verify_checksum "$version" "$appimage_path"

    # Extract AppImage
    extract_appimage "$appimage_path"

    # Install binary
    install_binary

    # Verify installation
    verify_installation "$version"

    # Store version info
    store_version "$version"

    echo ""
    log_info "========================================="
    log_info "WezTerm installation completed successfully!"
    log_info "Version: $version"
    log_info "Binary: $INSTALL_DIR/wezterm-mux-server"
    log_info "========================================="
}

# Run main function with all arguments
main "$@"
