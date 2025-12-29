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

# Track if we need to use sudo for docker commands
USE_SUDO=false

# =============================================================================
# Prerequisite Functions
# =============================================================================

detect_os() {
  IS_UBUNTU_DEBIAN=false
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" == "ubuntu" || "$ID" == "debian" || "$ID_LIKE" == *"ubuntu"* || "$ID_LIKE" == *"debian"* ]]; then
      IS_UBUNTU_DEBIAN=true
    fi
  fi
}

install_docker() {
  echo -e "${BLUE}Installing Docker...${NC}"
  echo ""

  # Remove old versions
  sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

  # Install prerequisites
  sudo apt-get update
  sudo apt-get install -y ca-certificates curl gnupg

  # Add Docker's official GPG key
  sudo install -m 0755 -d /etc/apt/keyrings
  if [ -f /etc/apt/keyrings/docker.gpg ]; then
    sudo rm /etc/apt/keyrings/docker.gpg
  fi
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  # Set up repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  # Install Docker
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Start and enable Docker
  sudo systemctl start docker
  sudo systemctl enable docker

  echo -e "${GREEN}✓ Docker installed successfully${NC}"
  echo ""
}

add_user_to_docker_group() {
  echo -e "${BLUE}Adding $USER to docker group...${NC}"
  sudo usermod -aG docker $USER
  echo -e "${GREEN}✓ Added $USER to docker group${NC}"
  echo ""
}

handle_session_refresh() {
  echo -e "${YELLOW}Session refresh required${NC}"
  echo ""
  echo "Your group membership has changed but your current session"
  echo "doesn't reflect it yet. Choose how to proceed:"
  echo ""
  echo "  1) Continue with sudo for Docker commands (recommended)"
  echo "  2) Restart this script with new group (uses 'sg' command)"
  echo "  3) Exit - I'll log out and back in manually"
  echo ""
  read -p "Choose [1/2/3]: " session_choice

  case $session_choice in
    1)
      USE_SUDO=true
      echo ""
      echo -e "${GREEN}Continuing with sudo for Docker commands...${NC}"
      echo ""
      ;;
    2)
      echo ""
      echo "Restarting script with docker group..."
      # Pass all original arguments and preserve working directory
      exec sg docker -c "cd $(pwd) && $0 $*"
      ;;
    *)
      echo ""
      echo "Please log out and log back in, then run:"
      echo "  ./setup.sh"
      echo ""
      exit 0
      ;;
  esac
}

start_docker_daemon() {
  echo -e "${BLUE}Starting Docker daemon...${NC}"
  sudo systemctl start docker
  sudo systemctl enable docker
  echo -e "${GREEN}✓ Docker started${NC}"
  echo ""
}

install_docker_compose() {
  echo -e "${BLUE}Installing Docker Compose plugin...${NC}"
  sudo apt-get update
  sudo apt-get install -y docker-compose-plugin
  echo -e "${GREEN}✓ Docker Compose installed${NC}"
  echo ""
}

# Helper to run docker commands (with sudo if needed)
docker_cmd() {
  if [ "$USE_SUDO" = true ]; then
    sudo docker "$@"
  else
    docker "$@"
  fi
}

check_prerequisites() {
  detect_os

  # Check if running as root
  if [ "$EUID" -eq 0 ]; then
    echo -e "${YELLOW}Note: Running as root. Consider using a regular user with sudo access.${NC}"
    echo ""
  fi

  # -------------------------------------------------------------------------
  # 1. Check if Docker is installed
  # -------------------------------------------------------------------------
  if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed.${NC}"
    echo ""

    if [ "$IS_UBUNTU_DEBIAN" = true ]; then
      read -p "Would you like to install Docker now? (Y/n): " install_choice
      if [[ ! "$install_choice" =~ ^[Nn]$ ]]; then
        install_docker
        add_user_to_docker_group
        handle_session_refresh
      else
        echo ""
        echo "Please install Docker manually:"
        echo "  https://docs.docker.com/engine/install/ubuntu/"
        echo ""
        exit 1
      fi
    else
      echo "Please install Docker first:"
      echo "  https://docs.docker.com/engine/install/"
      echo ""
      exit 1
    fi
  fi

  # -------------------------------------------------------------------------
  # 2. Check if Docker daemon is accessible
  # -------------------------------------------------------------------------
  if ! docker_cmd info &> /dev/null 2>&1; then
    DOCKER_ERROR=$(docker info 2>&1) || true

    if echo "$DOCKER_ERROR" | grep -qi "permission denied"; then
      # Check if user is already in docker group (session just needs refresh)
      if id -nG "$USER" 2>/dev/null | grep -qw docker; then
        echo -e "${YELLOW}You're in the docker group, but your session needs to be refreshed.${NC}"
        echo ""
        handle_session_refresh
      else
        echo -e "${YELLOW}Your user is not in the docker group.${NC}"
        echo ""
        read -p "Would you like to add $USER to the docker group? (Y/n): " add_choice
        if [[ ! "$add_choice" =~ ^[Nn]$ ]]; then
          add_user_to_docker_group
          handle_session_refresh
        else
          echo ""
          echo "Please add yourself to the docker group manually:"
          echo "  sudo usermod -aG docker \$USER"
          echo ""
          echo "Then log out and back in, and run this script again."
          exit 1
        fi
      fi
    elif echo "$DOCKER_ERROR" | grep -qi "is the docker daemon running\|cannot connect"; then
      echo -e "${YELLOW}Docker daemon is not running.${NC}"
      echo ""
      read -p "Would you like to start Docker now? (Y/n): " start_choice
      if [[ ! "$start_choice" =~ ^[Nn]$ ]]; then
        start_docker_daemon
      else
        echo ""
        echo "Please start Docker manually:"
        echo "  sudo systemctl start docker"
        echo ""
        exit 1
      fi
    else
      echo -e "${RED}Cannot connect to Docker daemon.${NC}"
      echo ""
      echo "Error: $DOCKER_ERROR"
      echo ""
      exit 1
    fi
  fi

  # -------------------------------------------------------------------------
  # 3. Check for Docker Compose
  # -------------------------------------------------------------------------
  if ! docker_cmd compose version &> /dev/null 2>&1; then
    echo -e "${YELLOW}Docker Compose plugin is not installed.${NC}"
    echo ""

    if [ "$IS_UBUNTU_DEBIAN" = true ]; then
      read -p "Would you like to install Docker Compose now? (Y/n): " compose_choice
      if [[ ! "$compose_choice" =~ ^[Nn]$ ]]; then
        install_docker_compose
      else
        echo ""
        echo "Please install Docker Compose manually:"
        echo "  sudo apt-get install docker-compose-plugin"
        echo ""
        exit 1
      fi
    else
      echo "Please install Docker Compose:"
      echo "  https://docs.docker.com/compose/install/"
      echo ""
      exit 1
    fi
  fi

  # All checks passed
  echo -e "${GREEN}✓ Docker and Docker Compose are ready${NC}"
  echo ""
}

# =============================================================================
# Main Script
# =============================================================================

echo -e "${BLUE}Checkend${NC} Community Edition Setup"
echo "================================"
echo ""

# Run prerequisite checks (may set USE_SUDO=true)
check_prerequisites

# Clone or update the main Checkend repository
CHECKEND_DIR="./checkend"

if [ -d "$CHECKEND_DIR" ]; then
  echo -e "${YELLOW}Checkend source found.${NC}"
  read -p "Do you want to update it? (Y/n): " update_repo
  if [[ ! "$update_repo" =~ ^[Nn]$ ]]; then
    echo -n "Updating Checkend source... "
    cd "$CHECKEND_DIR"
    git pull --quiet
    cd ..
    echo -e "${GREEN}done${NC}"
  fi
  echo ""
else
  echo -e "${BLUE}Version${NC}"
  echo "Which version do you want to install?"
  echo "  - Leave empty for latest (recommended for trying out)"
  echo "  - Or specify a version tag like 'v1.0.0' (recommended for production)"
  echo ""
  read -p "Version [latest]: " VERSION
  echo ""

  echo -n "Cloning Checkend source... "
  if [ -z "$VERSION" ] || [ "$VERSION" = "latest" ]; then
    git clone --quiet https://github.com/Checkend/checkend.git "$CHECKEND_DIR"
  else
    git clone --quiet -b "$VERSION" --single-branch https://github.com/Checkend/checkend.git "$CHECKEND_DIR"
  fi
  echo -e "${GREEN}done${NC}"
  echo ""
fi

ENV_FILE=".env"
EXISTING_POSTGRES_PASSWORD=""
EXISTING_SECRET_KEY_BASE=""

# Check if .env already exists
if [ -f "$ENV_FILE" ]; then
  echo -e "${YELLOW}Existing .env file found.${NC}"

  # Extract existing secrets
  EXISTING_POSTGRES_PASSWORD=$(grep "^POSTGRES_PASSWORD=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2)
  EXISTING_SECRET_KEY_BASE=$(grep "^SECRET_KEY_BASE=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2)

  read -p "Do you want to reconfigure? (y/N): " overwrite
  if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
    echo "Setup complete. Keeping existing configuration."
    exit 0
  fi
  echo ""
fi

# Generate or preserve secrets
echo -e "${BLUE}Configuring secrets...${NC}"

if [ -n "$EXISTING_SECRET_KEY_BASE" ]; then
  SECRET_KEY_BASE="$EXISTING_SECRET_KEY_BASE"
  echo "  SECRET_KEY_BASE: preserved"
else
  SECRET_KEY_BASE=$(openssl rand -hex 64)
  echo "  SECRET_KEY_BASE: generated"
fi

if [ -n "$EXISTING_POSTGRES_PASSWORD" ]; then
  POSTGRES_PASSWORD="$EXISTING_POSTGRES_PASSWORD"
  echo "  POSTGRES_PASSWORD: preserved (matches existing database)"
else
  POSTGRES_PASSWORD=$(openssl rand -hex 32)
  echo "  POSTGRES_PASSWORD: generated"
fi

echo -e "${GREEN}Secrets configured.${NC}"
echo ""

# Ask about deployment mode
echo -e "${BLUE}Deployment Mode${NC}"
echo "How will you expose Checkend to the web?"
echo ""
echo "  1) Direct - Checkend handles SSL via Let's Encrypt (ports 80/443)"
echo "  2) Reverse Proxy - You'll use nginx, Caddy, Traefik, etc."
echo ""
read -p "Choose [1/2]: " DEPLOY_MODE
echo ""

THRUSTER_TLS_DOMAIN=""

case $DEPLOY_MODE in
  1)
    echo -e "${BLUE}Direct Mode - SSL Configuration${NC}"
    echo "Enter your domain for automatic Let's Encrypt SSL."
    echo ""
    read -p "Domain (e.g., checkend.example.com): " THRUSTER_TLS_DOMAIN
    while [[ -z "$THRUSTER_TLS_DOMAIN" ]]; do
      echo -e "${RED}Domain is required for SSL.${NC}"
      read -p "Domain: " THRUSTER_TLS_DOMAIN
    done
    echo ""
    ;;
  2)
    echo -e "${GREEN}Reverse Proxy Mode selected.${NC}"
    echo "Checkend will listen on port 3000. Configure your proxy to forward to it."
    echo ""
    ;;
  *)
    DEPLOY_MODE="2"
    echo -e "${YELLOW}Invalid choice. Defaulting to Reverse Proxy mode.${NC}"
    echo "Checkend will listen on port 3000. Configure your proxy to forward to it."
    echo ""
    ;;
esac

# Write .env file
echo -e "${BLUE}Writing configuration...${NC}"

cat > "$ENV_FILE" << EOF
# Checkend Community Edition Configuration
# Generated by setup.sh on $(date)

# =============================================================================
# REQUIRED (auto-generated)
# =============================================================================

SECRET_KEY_BASE=$SECRET_KEY_BASE
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
EOF

if [ -n "$THRUSTER_TLS_DOMAIN" ]; then
  cat >> "$ENV_FILE" << EOF

# Domain for automatic Let's Encrypt SSL
THRUSTER_TLS_DOMAIN=$THRUSTER_TLS_DOMAIN
EOF
fi

echo -e "${GREEN}Configuration saved to .env${NC}"

# Create compose.override.yml based on deployment mode
if [ "$DEPLOY_MODE" = "1" ]; then
  echo -e "${BLUE}Creating compose.override.yml for direct SSL access...${NC}"
  cat > compose.override.yml << 'EOF'
services:
  app:
    ports:
      - "80:80"
      - "443:443"
    environment:
      - THRUSTER_TLS_DOMAIN=${THRUSTER_TLS_DOMAIN:-}
EOF
  echo -e "${GREEN}Created compose.override.yml (ports 80/443 with SSL)${NC}"
elif [ "$DEPLOY_MODE" = "2" ]; then
  echo -e "${BLUE}Creating compose.override.yml for reverse proxy access...${NC}"
  cat > compose.override.yml << 'EOF'
services:
  app:
    ports:
      - "3000:80"
EOF
  echo -e "${GREEN}Created compose.override.yml (port 3000)${NC}"
fi
echo ""

# Determine the docker compose command to show
if [ "$USE_SUDO" = true ]; then
  COMPOSE_CMD="sudo docker compose"
else
  COMPOSE_CMD="docker compose"
fi

# Next steps
echo -e "${BLUE}Setup complete!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo ""

if [ "$DEPLOY_MODE" = "1" ]; then
  echo "1. Ensure your domain points to this server:"
  echo "   $THRUSTER_TLS_DOMAIN → $(curl -s ifconfig.me 2>/dev/null || echo '<your-server-ip>')"
  echo ""
  echo "2. Ensure ports 80 and 443 are open in your firewall"
  echo ""
  echo "3. Build and start Checkend:"
  echo "   $COMPOSE_CMD up -d --build"
  echo ""
  echo "4. Visit https://$THRUSTER_TLS_DOMAIN and create your account"
else
  echo "1. Build and start Checkend:"
  echo "   $COMPOSE_CMD up -d --build"
  echo ""
  echo "2. Configure your reverse proxy to forward to port 3000"
  echo "   Example nginx: proxy_pass http://localhost:3000;"
  echo "   Example Caddy: reverse_proxy localhost:3000"
  echo ""
  echo "3. Visit your domain and create your account"
fi

# Mention systemd service option on Linux
if [[ "$(uname -s)" == "Linux" ]]; then
  echo ""
  echo -e "${BLUE}Optional: Run as a system service${NC}"
  echo "To start Checkend automatically on boot:"
  echo "  sudo ./install-service.sh"
fi

# Remind about logging out if using sudo mode
if [ "$USE_SUDO" = true ]; then
  echo ""
  echo -e "${YELLOW}Note:${NC} You're using sudo for Docker commands because your session"
  echo "hasn't picked up the docker group yet. After logging out and back in,"
  echo "you can run Docker commands without sudo."
fi

echo ""
echo -e "${GREEN}Done!${NC}"
