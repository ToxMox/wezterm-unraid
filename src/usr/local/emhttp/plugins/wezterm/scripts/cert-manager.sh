#!/bin/bash
#
# WezTerm Certificate Manager
# Manages TLS certificates for WezTerm Server on Unraid
#

set -euo pipefail

# Certificate directory
CERT_DIR="/boot/config/plugins/wezterm/certs"
CLIENT_DIR="${CERT_DIR}/clients"

# CA and server certificate files
CA_KEY="${CERT_DIR}/ca.key"
CA_CERT="${CERT_DIR}/ca.crt"
SERVER_KEY="${CERT_DIR}/server.key"
SERVER_CERT="${CERT_DIR}/server.crt"
SERVER_CSR="${CERT_DIR}/server.csr"
CA_SERIAL="${CERT_DIR}/ca.srl"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Sanitize certificate name (alphanumeric, dash, underscore only)
sanitize_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid certificate name: $name"
        log_error "Name must contain only alphanumeric characters, dashes, and underscores"
        exit 1
    fi
    echo "$name"
}

# Initialize CA and server certificates
cmd_init() {
    log_info "Initializing WezTerm Certificate Authority..."

    # Create certificate directories
    mkdir -p "$CERT_DIR" "$CLIENT_DIR"
    chmod 700 "$CERT_DIR"

    # Check if CA already exists
    if [[ -f "$CA_KEY" ]] || [[ -f "$CA_CERT" ]]; then
        log_error "Certificate Authority already exists!"
        log_error "If you want to recreate it, manually delete:"
        log_error "  $CA_KEY"
        log_error "  $CA_CERT"
        exit 1
    fi

    # Generate CA private key (4096-bit RSA, 10 years)
    log_info "Generating CA private key..."
    openssl genrsa -out "$CA_KEY" 4096 2>/dev/null
    chmod 600 "$CA_KEY"

    # Generate self-signed CA certificate (10 years)
    log_info "Generating CA certificate..."
    openssl req -new -x509 -days 3650 -key "$CA_KEY" -out "$CA_CERT" \
        -subj "/CN=WezTerm-Unraid-CA/O=Unraid/OU=WezTerm" 2>/dev/null
    chmod 644 "$CA_CERT"

    log_info "Certificate Authority created successfully"
    log_info "CA Certificate: $CA_CERT"

    # Generate server certificate
    log_info "Generating server certificate..."

    # Generate server private key
    openssl genrsa -out "$SERVER_KEY" 4096 2>/dev/null
    chmod 600 "$SERVER_KEY"

    # Get server hostname and IP
    local hostname
    hostname=$(hostname)

    local ip
    ip=$(hostname -I | awk '{print $1}' || echo "127.0.0.1")

    # Generate server CSR
    openssl req -new -key "$SERVER_KEY" -out "$SERVER_CSR" \
        -subj "/CN=${hostname}/O=Unraid/OU=WezTerm Server" 2>/dev/null

    # Create SAN configuration
    local san_config
    san_config=$(mktemp)
    cat > "$san_config" <<EOF
subjectAltName=DNS:${hostname},DNS:${hostname}.local,DNS:localhost,IP:${ip},IP:127.0.0.1
EOF

    # Sign server certificate with CA (10 years)
    openssl x509 -req -days 3650 -in "$SERVER_CSR" \
        -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
        -out "$SERVER_CERT" -extfile "$san_config" 2>/dev/null

    chmod 644 "$SERVER_CERT"
    rm -f "$SERVER_CSR" "$san_config"

    log_info "Server certificate created successfully"
    log_info "Server Certificate: $SERVER_CERT"
    log_info ""
    log_info "Certificate initialization complete!"
    log_info "You can now generate client certificates with: $0 generate <name>"
}

# Generate client certificate
cmd_generate() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        log_error "Usage: $0 generate <name>"
        exit 1
    fi

    # Sanitize name
    name=$(sanitize_name "$name")

    # Check if CA exists
    if [[ ! -f "$CA_KEY" ]] || [[ ! -f "$CA_CERT" ]]; then
        log_error "Certificate Authority not initialized"
        log_error "Run: $0 init"
        exit 1
    fi

    # Check if client certificate already exists
    local client_key="${CLIENT_DIR}/${name}.key"
    local client_cert="${CLIENT_DIR}/${name}.crt"
    local client_csr="${CLIENT_DIR}/${name}.csr"

    if [[ -f "$client_key" ]] || [[ -f "$client_cert" ]]; then
        log_error "Certificate for '$name' already exists!"
        log_error "If you want to recreate it, revoke it first: $0 revoke $name"
        exit 1
    fi

    log_info "Generating client certificate for: $name"

    # Generate client private key
    log_info "Generating private key..."
    openssl genrsa -out "$client_key" 4096 2>/dev/null
    chmod 600 "$client_key"

    # Generate client CSR
    openssl req -new -key "$client_key" -out "$client_csr" \
        -subj "/CN=${name}/O=Unraid/OU=WezTerm Client" 2>/dev/null

    # Sign client certificate with CA (1 year)
    log_info "Signing certificate with CA..."
    openssl x509 -req -days 365 -in "$client_csr" \
        -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial \
        -out "$client_cert" 2>/dev/null

    chmod 644 "$client_cert"
    rm -f "$client_csr"

    log_info "Client certificate created successfully"
    log_info "Certificate: $client_cert"
    log_info "Private key: $client_key"
    log_info ""
    log_info "Create a downloadable bundle with: $0 bundle $name"
}

# Revoke (delete) client certificate
cmd_revoke() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        log_error "Usage: $0 revoke <name>"
        exit 1
    fi

    # Sanitize name
    name=$(sanitize_name "$name")

    local client_key="${CLIENT_DIR}/${name}.key"
    local client_cert="${CLIENT_DIR}/${name}.crt"

    # Check if certificate exists
    if [[ ! -f "$client_key" ]] && [[ ! -f "$client_cert" ]]; then
        log_error "Certificate for '$name' not found"
        exit 1
    fi

    log_warn "Revoking certificate for: $name"

    # Delete certificate files
    rm -f "$client_key" "$client_cert" "${CLIENT_DIR}/${name}.csr"

    log_info "Certificate for '$name' has been revoked and deleted"
}

# List all certificates
cmd_list() {
    # Check if CA exists
    if [[ ! -f "$CA_CERT" ]]; then
        echo "[]"
        return 0
    fi

    local certs=()

    # Add CA certificate
    local ca_created
    ca_created=$(stat -c %Y "$CA_CERT" 2>/dev/null || echo "0")
    ca_created=$(date -d "@${ca_created}" -Iseconds 2>/dev/null || echo "unknown")

    certs+=("{\"name\":\"ca\",\"type\":\"ca\",\"created\":\"${ca_created}\",\"status\":\"active\"}")

    # Add server certificate
    if [[ -f "$SERVER_CERT" ]]; then
        local server_created
        server_created=$(stat -c %Y "$SERVER_CERT" 2>/dev/null || echo "0")
        server_created=$(date -d "@${server_created}" -Iseconds 2>/dev/null || echo "unknown")

        certs+=("{\"name\":\"server\",\"type\":\"server\",\"created\":\"${server_created}\",\"status\":\"active\"}")
    fi

    # Add client certificates
    if [[ -d "$CLIENT_DIR" ]]; then
        while IFS= read -r cert_file; do
            if [[ -f "$cert_file" ]]; then
                local cert_name
                cert_name=$(basename "$cert_file" .crt)

                local cert_created
                cert_created=$(stat -c %Y "$cert_file" 2>/dev/null || echo "0")
                cert_created=$(date -d "@${cert_created}" -Iseconds 2>/dev/null || echo "unknown")

                # Check if key exists
                local status="active"
                if [[ ! -f "${CLIENT_DIR}/${cert_name}.key" ]]; then
                    status="incomplete"
                fi

                # Get expiration date
                local expiry
                expiry=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "unknown")

                # Check if expired
                if [[ "$expiry" != "unknown" ]]; then
                    local expiry_epoch
                    expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || echo "0")
                    local now_epoch
                    now_epoch=$(date +%s)

                    if [[ $expiry_epoch -lt $now_epoch ]]; then
                        status="expired"
                    fi
                fi

                certs+=("{\"name\":\"${cert_name}\",\"type\":\"client\",\"created\":\"${cert_created}\",\"expiry\":\"${expiry}\",\"status\":\"${status}\"}")
            fi
        done < <(find "$CLIENT_DIR" -maxdepth 1 -name "*.crt" 2>/dev/null | sort)
    fi

    # Output JSON array
    echo -n "["
    local first=true
    for cert in "${certs[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            echo -n ","
        fi
        echo -n "$cert"
    done
    echo "]"
}

# Create downloadable bundle for client
cmd_bundle() {
    local name="${1:-}"

    if [[ -z "$name" ]]; then
        log_error "Usage: $0 bundle <name>"
        exit 1
    fi

    # Sanitize name
    name=$(sanitize_name "$name")

    local client_key="${CLIENT_DIR}/${name}.key"
    local client_cert="${CLIENT_DIR}/${name}.crt"

    # Check if certificate exists
    if [[ ! -f "$client_key" ]] || [[ ! -f "$client_cert" ]]; then
        log_error "Certificate for '$name' not found"
        log_error "Generate it first with: $0 generate $name"
        exit 1
    fi

    # Create temporary directory for bundle
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" EXIT

    local bundle_dir="${temp_dir}/wezterm-certs-${name}"
    mkdir -p "$bundle_dir"

    log_info "Creating certificate bundle for: $name"

    # Copy certificates
    cp "$CA_CERT" "${bundle_dir}/ca.crt"
    cp "$client_cert" "${bundle_dir}/client.crt"
    cp "$client_key" "${bundle_dir}/client.key"

    # Get server hostname and IP for example config
    local hostname
    hostname=$(hostname)
    local ip
    ip=$(hostname -I | awk '{print $1}' || echo "YOUR_UNRAID_IP")

    # Create example WezTerm config
    cat > "${bundle_dir}/wezterm-client.lua" <<'EOF'
-- WezTerm Client Configuration
-- Add this to your ~/.wezterm.lua or ~/.config/wezterm/wezterm.lua

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Configure TLS client connection to Unraid WezTerm Server
-- IMPORTANT: Update the paths below to where you extracted the certificates
config.tls_clients = {
  {
    name = "unraid",
EOF

    echo "    remote_address = \"${ip}:8080\"," >> "${bundle_dir}/wezterm-client.lua"

    cat >> "${bundle_dir}/wezterm-client.lua" <<'EOF'

    -- Update these paths to match where you saved the certificates
    pem_private_key = "/path/to/client.key",
    pem_cert = "/path/to/client.crt",
    pem_ca = "/path/to/ca.crt",
  },
}

-- Then connect with: wezterm connect unraid

return config
EOF

    # Create README
    cat > "${bundle_dir}/README.txt" <<EOF
WezTerm Client Certificates for: ${name}
=====================================

This bundle contains the certificates needed to connect to your WezTerm Server
on Unraid.

Files included:
  - ca.crt          CA certificate (validates server identity)
  - client.crt      Client certificate (your identity)
  - client.key      Client private key (keep this secure!)
  - wezterm-client.lua  Example configuration

Setup Instructions:
-------------------

1. Extract this bundle to a secure location on your client machine
   Example: ~/.wezterm-certs/

2. Set appropriate permissions (Linux/macOS):
   chmod 600 client.key
   chmod 644 client.crt ca.crt

3. Edit your WezTerm configuration file:
   - Linux/macOS: ~/.wezterm.lua or ~/.config/wezterm/wezterm.lua
   - Windows: %USERPROFILE%\.wezterm.lua

   Add the contents of wezterm-client.lua to your config, updating:
   - remote_address: Your Unraid server IP/hostname and port
   - pem_private_key: Full path to client.key
   - pem_cert: Full path to client.crt
   - pem_ca: Full path to ca.crt

4. Connect to your Unraid WezTerm Server:
   wezterm connect unraid

Security Notes:
---------------
- Keep client.key secure and never share it
- The client certificate expires after 1 year
- If compromised, contact your admin to revoke the certificate

Server Details:
---------------
Hostname: ${hostname}
IP Address: ${ip}
Port: 8080 (default)

EOF

    # Create zip bundle
    local bundle_name="wezterm-certs-${name}.zip"
    local bundle_path="${CERT_DIR}/${bundle_name}"

    cd "$temp_dir"
    zip -q -r "$bundle_path" "wezterm-certs-${name}"
    chmod 644 "$bundle_path"

    log_info "Certificate bundle created: $bundle_path"
    log_info ""
    log_info "Download this file and extract it on your client machine."
    log_info "Follow the instructions in README.txt to configure WezTerm."

    # Output JSON for web UI consumption
    echo "{\"success\":true,\"bundle\":\"${bundle_path}\",\"name\":\"${bundle_name}\"}"
}

# Show usage
show_usage() {
    cat <<EOF
WezTerm Certificate Manager

Usage: $0 <command> [arguments]

Commands:
  init                    Initialize Certificate Authority and server certificate
  generate <name>         Generate a new client certificate
  revoke <name>           Revoke (delete) a client certificate
  list                    List all certificates (JSON output)
  bundle <name>           Create downloadable bundle for client

Examples:
  $0 init                 # First-time setup
  $0 generate laptop      # Create cert for laptop
  $0 bundle laptop        # Create downloadable bundle
  $0 list                 # Show all certificates
  $0 revoke laptop        # Delete laptop certificate

Certificate Storage:
  CA & Server: $CERT_DIR/
  Clients:     $CLIENT_DIR/

EOF
}

# Main command dispatcher
main() {
    local command="${1:-}"

    if [[ -z "$command" ]]; then
        show_usage
        exit 1
    fi

    case "$command" in
        init)
            cmd_init
            ;;
        generate)
            shift
            cmd_generate "$@"
            ;;
        revoke)
            shift
            cmd_revoke "$@"
            ;;
        list)
            cmd_list
            ;;
        bundle)
            shift
            cmd_bundle "$@"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
