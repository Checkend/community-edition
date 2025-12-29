#!/usr/bin/env bash
set -e

# Colors for output
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  NC=''
fi

SERVICE_NAME="checkend"
INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${BLUE}Checkend Service Installer${NC}"
echo "==========================="
echo ""

# Check if running on Linux
if [[ "$(uname -s)" != "Linux" ]]; then
  echo -e "${RED}This script only supports Linux with systemd.${NC}"
  echo ""
  echo "For macOS, Docker Desktop manages containers automatically."
  echo "For other systems, consult your init system's documentation."
  echo ""
  exit 1
fi

# Check if systemd is available
if ! command -v systemctl &> /dev/null; then
  echo -e "${RED}systemd is not available on this system.${NC}"
  echo ""
  echo "This script requires systemd to manage the service."
  echo "For other init systems (e.g., OpenRC, runit), please configure manually."
  echo ""
  exit 1
fi

# Check for root/sudo
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}This script must be run as root or with sudo.${NC}"
  echo ""
  echo "Usage:"
  echo "  sudo ./install-service.sh"
  echo ""
  exit 1
fi

# Check if setup has been run
if [[ ! -f "$INSTALL_DIR/.env" ]]; then
  echo -e "${RED}Configuration not found.${NC}"
  echo ""
  echo "Please run setup.sh first:"
  echo "  ./setup.sh"
  echo ""
  exit 1
fi

# Check if compose.yml exists
if [[ ! -f "$INSTALL_DIR/compose.yml" ]] && [[ ! -f "$INSTALL_DIR/docker-compose.yml" ]]; then
  echo -e "${RED}Docker Compose file not found.${NC}"
  echo ""
  exit 1
fi

# Determine docker compose command with full paths
DOCKER_PATH=$(command -v docker)
if [ -z "$DOCKER_PATH" ]; then
  echo -e "${RED}Docker is not installed.${NC}"
  exit 1
fi

if docker compose version &> /dev/null; then
  COMPOSE_CMD="$DOCKER_PATH compose"
elif command -v docker-compose &> /dev/null; then
  COMPOSE_CMD=$(command -v docker-compose)
else
  echo -e "${RED}Docker Compose is not installed.${NC}"
  exit 1
fi

echo -e "${BLUE}Installation directory:${NC} $INSTALL_DIR"
echo -e "${BLUE}Service name:${NC} $SERVICE_NAME"
echo ""

# Check if service already exists
if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
  echo -e "${YELLOW}Service '${SERVICE_NAME}' already exists.${NC}"
  read -p "Do you want to reinstall it? (y/N): " reinstall
  if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
  fi
  echo ""
  echo -e "${BLUE}Stopping existing service...${NC}"
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true
fi

# Create systemd service file
echo -e "${BLUE}Creating systemd service...${NC}"

cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Checkend Community Edition
Documentation=https://github.com/checkend/community-edition
After=network-online.target docker.service
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR
ExecStart=$COMPOSE_CMD up -d --remove-orphans
ExecStop=$COMPOSE_CMD down
ExecReload=$COMPOSE_CMD up -d --remove-orphans
TimeoutStartSec=300
TimeoutStopSec=120

# Restart configuration
Restart=on-failure
RestartSec=10

# Security hardening (where possible with Docker)
ProtectSystem=full
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}Service file created.${NC}"

# Reload systemd
echo -e "${BLUE}Reloading systemd...${NC}"
systemctl daemon-reload
echo -e "${GREEN}systemd reloaded.${NC}"

# Enable service
echo -e "${BLUE}Enabling service to start on boot...${NC}"
systemctl enable "$SERVICE_NAME"
echo -e "${GREEN}Service enabled.${NC}"
echo ""

# Ask to start now
read -p "Do you want to start Checkend now? (Y/n): " start_now
if [[ ! "$start_now" =~ ^[Nn]$ ]]; then
  echo ""
  echo -e "${BLUE}Starting Checkend...${NC}"
  if systemctl start "$SERVICE_NAME"; then
    echo -e "${GREEN}Checkend started.${NC}"
  else
    echo ""
    echo -e "${RED}Failed to start Checkend.${NC}"
    echo ""
    echo "View the error with:"
    echo "  sudo journalctl -u $SERVICE_NAME -n 50"
    echo ""
    echo "You can also try running Docker Compose directly:"
    echo "  cd $INSTALL_DIR"
    echo "  docker compose up"
    echo ""
    exit 1
  fi
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo -e "${BLUE}Useful commands:${NC}"
echo ""
echo "  Check status:"
echo "    sudo systemctl status $SERVICE_NAME"
echo ""
echo "  View logs:"
echo "    sudo journalctl -u $SERVICE_NAME -f"
echo ""
echo "  Stop service:"
echo "    sudo systemctl stop $SERVICE_NAME"
echo ""
echo "  Start service:"
echo "    sudo systemctl start $SERVICE_NAME"
echo ""
echo "  Restart service:"
echo "    sudo systemctl restart $SERVICE_NAME"
echo ""
echo "  Disable auto-start on boot:"
echo "    sudo systemctl disable $SERVICE_NAME"
echo ""
echo "  Uninstall service:"
echo "    sudo systemctl stop $SERVICE_NAME"
echo "    sudo systemctl disable $SERVICE_NAME"
echo "    sudo rm /etc/systemd/system/${SERVICE_NAME}.service"
echo "    sudo systemctl daemon-reload"
echo ""
