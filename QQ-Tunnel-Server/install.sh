#!/bin/bash
#
# QQ-Tunnel Server Installer
# Installs QQ-Tunnel to /opt/qq-tunnel and sets up systemd service
#

set -e

INSTALL_DIR="/opt/qq-tunnel"
SERVICE_NAME="qq-tunnel"
CLI_LINK="/usr/local/bin/qq-tunnel"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "============================================"
echo "       QQ-Tunnel Server Installer"
echo "============================================"
echo -e "${NC}"

# --- Check root ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root: sudo bash install.sh${NC}"
    exit 1
fi

# --- Check Python 3 ---
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}Python3 not found. Installing...${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq python3
    elif command -v dnf &> /dev/null; then
        dnf install -y python3
    elif command -v yum &> /dev/null; then
        yum install -y python3
    else
        echo -e "${RED}Cannot install Python3 automatically. Please install it manually.${NC}"
        exit 1
    fi
fi

PYTHON_VERSION=$(python3 --version 2>&1)
echo -e "${GREEN}Found: ${PYTHON_VERSION}${NC}"

# --- Stop existing service if running ---
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo -e "${YELLOW}Stopping existing QQ-Tunnel service...${NC}"
    systemctl stop "$SERVICE_NAME"
fi

# --- Stop systemd-resolved if using port 53 ---
if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    echo -e "${YELLOW}systemd-resolved is using port 53.${NC}"
    read -p "Disable systemd-resolved to free port 53? (yes/no) [yes]: " disable_resolved
    disable_resolved=${disable_resolved:-yes}
    if [ "$disable_resolved" = "yes" ]; then
        systemctl stop systemd-resolved
        systemctl disable systemd-resolved
        # Set a fallback DNS so the server doesn't lose resolution
        if [ -L /etc/resolv.conf ]; then
            rm -f /etc/resolv.conf
        fi
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        echo "nameserver 1.1.1.1" >> /etc/resolv.conf
        echo -e "${GREEN}systemd-resolved disabled. DNS set to 8.8.8.8 / 1.1.1.1${NC}"
    else
        echo -e "${YELLOW}Warning: QQ-Tunnel may fail to bind port 53 if systemd-resolved is active.${NC}"
    fi
fi

# --- Increase file descriptor limit ---
echo -e "${CYAN}Configuring system limits...${NC}"
LIMITS_CONF="/etc/security/limits.conf"
if ! grep -q "qq-tunnel" "$LIMITS_CONF" 2>/dev/null; then
    echo "# QQ-Tunnel file descriptor limits" >> "$LIMITS_CONF"
    echo "root soft nofile 65536" >> "$LIMITS_CONF"
    echo "root hard nofile 65536" >> "$LIMITS_CONF"
fi

# --- Copy files ---
echo -e "${CYAN}Installing to ${INSTALL_DIR}...${NC}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$INSTALL_DIR/utility"

cp "$SCRIPT_DIR/tunnel.py"       "$INSTALL_DIR/tunnel.py"
cp "$SCRIPT_DIR/data_handler.py" "$INSTALL_DIR/data_handler.py"
cp "$SCRIPT_DIR/data_cap.py"     "$INSTALL_DIR/data_cap.py"
cp "$SCRIPT_DIR/setup.py"        "$INSTALL_DIR/setup.py"
cp "$SCRIPT_DIR/qq-tunnel"       "$INSTALL_DIR/qq-tunnel"
cp "$SCRIPT_DIR/utility/__init__.py"     "$INSTALL_DIR/utility/__init__.py"
cp "$SCRIPT_DIR/utility/base32.py"       "$INSTALL_DIR/utility/base32.py"
cp "$SCRIPT_DIR/utility/dns.py"          "$INSTALL_DIR/utility/dns.py"
cp "$SCRIPT_DIR/utility/socket_tools.py" "$INSTALL_DIR/utility/socket_tools.py"

# Preserve existing config if present
if [ -f "$INSTALL_DIR/config.json" ]; then
    echo -e "${YELLOW}Existing config.json preserved.${NC}"
fi

chmod +x "$INSTALL_DIR/qq-tunnel"

# --- Create CLI symlink ---
ln -sf "$INSTALL_DIR/qq-tunnel" "$CLI_LINK"
echo -e "${GREEN}CLI installed: qq-tunnel${NC}"

# --- Create systemd service ---
echo -e "${CYAN}Creating systemd service...${NC}"

cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=QQ-Tunnel DNS Tunnel Server
After=network.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/tunnel.py
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

# Security hardening
NoNewPrivileges=false
ProtectSystem=strict
ReadWritePaths=${INSTALL_DIR}
ProtectHome=true
PrivateTmp=true

StandardOutput=journal
StandardError=journal
SyslogIdentifier=qq-tunnel

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"

# --- Configure firewall ---
echo -e "${CYAN}Configuring firewall...${NC}"
if command -v ufw &> /dev/null; then
    ufw allow 53/udp > /dev/null 2>&1 && echo -e "${GREEN}UFW: allowed UDP 53${NC}"
    ufw allow 53/tcp > /dev/null 2>&1 && echo -e "${GREEN}UFW: allowed TCP 53${NC}"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=53/udp > /dev/null 2>&1
    firewall-cmd --permanent --add-port=53/tcp > /dev/null 2>&1
    firewall-cmd --reload > /dev/null 2>&1
    echo -e "${GREEN}firewalld: allowed port 53${NC}"
else
    echo -e "${YELLOW}No firewall tool detected. Make sure UDP port 53 is open.${NC}"
fi

# --- Done ---
echo ""
echo -e "${GREEN}${BOLD}============================================"
echo "       Installation Complete!"
echo "============================================${NC}"
echo ""
echo -e "Next steps:"
echo -e "  ${CYAN}1.${NC} Run the setup wizard:    ${BOLD}sudo qq-tunnel setup${NC}"
echo -e "  ${CYAN}2.${NC} Start the tunnel:        ${BOLD}sudo qq-tunnel start${NC}"
echo -e "  ${CYAN}3.${NC} Check status:            ${BOLD}sudo qq-tunnel status${NC}"
echo -e "  ${CYAN}4.${NC} View logs:               ${BOLD}sudo qq-tunnel logs${NC}"
echo ""
echo -e "${YELLOW}Don't forget to set up your Cloudflare DNS records:${NC}"
echo -e "  A  record:  ns1.yourdomain.com  ->  YOUR_SERVER_IP (DNS only, no proxy)"
echo -e "  NS record:  tunnel.yourdomain.com  ->  ns1.yourdomain.com"
echo ""
