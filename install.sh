#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  MTProxyMax Web Panel — One-Line Installer
#
#  This installs ONLY the web panel.
#  MTProxyMax must be installed separately first.
#
#  Based on MTProxyMax by SamNet Technologies
#  Original: https://github.com/SamNet-dev/MTProxyMax
#
#  Web Panel by ScannerVpn
#  https://github.com/ScannerVpn/MTProxyMax-WebPanel
#
#  License: MIT
# ═══════════════════════════════════════════════════════════════
set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/opt/mtproxymax"
WEBPANEL_DIR="${INSTALL_DIR}/webpanel"
WEBPANEL_REPO="https://github.com/ScannerVpn/MTProxyMax-WebPanel.git"

log_info()    { echo -e "  ${CYAN}[i]${NC} $1"; }
log_success() { echo -e "  ${GREEN}[✓]${NC} $1"; }
log_warn()    { echo -e "  ${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "  ${RED}[✗]${NC} $1" >&2; }

# Check root
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root"
    echo -e "  ${YELLOW}Try: sudo bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/ScannerVpn/MTProxyMax-WebPanel/main/install.sh)\"${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}${BOLD}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║     MTProxyMax Web Panel Installer v1.0.0    ║"
echo "  ║     by ScannerVpn                            ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Check if MTProxyMax is installed ──
if [ ! -f "${INSTALL_DIR}/mtproxymax" ] && [ ! -f "${INSTALL_DIR}/settings.conf" ]; then
    log_error "MTProxyMax is not installed!"
    echo ""
    echo -e "  ${YELLOW}Please install MTProxyMax first:${NC}"
    echo -e "  ${GREEN}sudo bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/SamNet-dev/MTProxyMax/main/install.sh)\"${NC}"
    echo ""
    echo -e "  ${DIM}Then run this installer again:${NC}"
    echo -e "  ${GREEN}sudo bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/ScannerVpn/MTProxyMax-WebPanel/main/install.sh)\"${NC}"
    exit 1
fi

log_success "MTProxyMax found"

# ── Install dependencies ──
if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
    log_info "Installing Python3..."
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq python3 2>/dev/null
    elif command -v yum &>/dev/null; then
        yum install -y -q python3 2>/dev/null
    elif command -v apk &>/dev/null; then
        apk add --no-cache python3 2>/dev/null
    fi
fi

PYTHON_CMD=""
command -v python3 &>/dev/null && PYTHON_CMD="python3"
command -v python &>/dev/null && [ -z "$PYTHON_CMD" ] && PYTHON_CMD="python"

if [ -z "$PYTHON_CMD" ]; then
    log_error "Python3 is required but not found"
    exit 1
fi

log_success "Python found: ${PYTHON_CMD}"

# ── Stop existing web panel if running ──
if systemctl is-active --quiet mtproxymax-webpanel 2>/dev/null; then
    log_info "Stopping existing web panel..."
    systemctl stop mtproxymax-webpanel 2>/dev/null || true
fi

# ── Install Web Panel ──
echo ""
log_info "Installing Web Panel..."

# Create directory structure
mkdir -p "${WEBPANEL_DIR}/www/static"

# Download from GitHub
TMPDIR=$(mktemp -d)
if git clone --depth 1 "$WEBPANEL_REPO" "$TMPDIR/webpanel-repo" 2>/dev/null; then
    # Copy server files
    if [ -d "$TMPDIR/webpanel-repo/server" ]; then
        cp -r "$TMPDIR/webpanel-repo/server/"* "${WEBPANEL_DIR}/" 2>/dev/null || true
    fi

    # Copy web files
    if [ -d "$TMPDIR/webpanel-repo/www" ]; then
        cp -r "$TMPDIR/webpanel-repo/www/"* "${WEBPANEL_DIR}/www/" 2>/dev/null || true
    fi

    log_success "Web Panel files downloaded"
else
    log_error "Failed to download from GitHub"
    rm -rf "$TMPDIR"
    exit 1
fi
rm -rf "$TMPDIR"

# Verify server.py exists
if [ ! -f "${WEBPANEL_DIR}/server.py" ]; then
    log_error "server.py not found after download"
    exit 1
fi

chmod +x "${WEBPANEL_DIR}/server.py" 2>/dev/null || true
log_success "Web Panel installed to ${WEBPANEL_DIR}"

# ── Generate auth token ──
WEBPANEL_TOKEN=$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 32)
WEBPANEL_PORT=8888

# Save web panel settings to settings.conf (append if not exists)
if [ -f "${INSTALL_DIR}/settings.conf" ]; then
    if ! grep -q "WEBPANEL_ENABLED" "${INSTALL_DIR}/settings.conf" 2>/dev/null; then
        cat >> "${INSTALL_DIR}/settings.conf" << EOF

# Web Panel
WEBPANEL_ENABLED='true'
WEBPANEL_PORT='${WEBPANEL_PORT}'
WEBPANEL_TOKEN='${WEBPANEL_TOKEN}'
EOF
    fi
fi

# ── Create systemd service ──
cat > /etc/systemd/system/mtproxymax-webpanel.service << EOF
[Unit]
Description=MTProxyMax Web Panel
After=network.target docker.service

[Service]
Type=simple
WorkingDirectory=${WEBPANEL_DIR}
Environment=INSTALL_DIR=${INSTALL_DIR}
Environment=MTPANEL_TOKEN=${WEBPANEL_TOKEN}
ExecStart=${PYTHON_CMD} ${WEBPANEL_DIR}/server.py ${WEBPANEL_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload 2>/dev/null || true
systemctl enable mtproxymax-webpanel 2>/dev/null || true
systemctl start mtproxymax-webpanel 2>/dev/null || true

# Wait a moment for service to start
sleep 2

# ── Get server IP ──
SERVER_IP=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null || \
            curl -s --max-time 3 https://ifconfig.me 2>/dev/null || \
            curl -s --max-time 3 https://icanhazip.com 2>/dev/null || \
            echo "YOUR_SERVER_IP")

# ── Check if service is running ──
if systemctl is-active --quiet mtproxymax-webpanel 2>/dev/null; then
    STATUS="${GREEN}RUNNING${NC}"
else
    STATUS="${RED}STOPPED${NC}"
fi

# ── Summary ──
echo ""
echo -e "${GREEN}${BOLD}  ════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}   WEB PANEL INSTALLATION COMPLETE${NC}"
echo -e "${GREEN}${BOLD}  ════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Status:${NC}     ${STATUS}"
echo -e "  ${BOLD}URL:${NC}        ${CYAN}http://${SERVER_IP}:${WEBPANEL_PORT}${NC}"
echo -e "  ${BOLD}Token:${NC}      ${YELLOW}${WEBPANEL_TOKEN}${NC}"
echo ""
echo -e "  ${DIM}Open the URL in your browser and enter the token to login${NC}"
echo ""
echo -e "  ${BOLD}Service Commands:${NC}"
echo -e "  ${GREEN}systemctl start mtproxymax-webpanel${NC}    Start"
echo -e "  ${GREEN}systemctl stop mtproxymax-webpanel${NC}     Stop"
echo -e "  ${GREEN}systemctl restart mtproxymax-webpanel${NC}  Restart"
echo -e "  ${GREEN}systemctl status mtproxymax-webpanel${NC}   Status"
echo -e "  ${GREEN}journalctl -u mtproxymax-webpanel -f${NC}   Logs"
echo ""
