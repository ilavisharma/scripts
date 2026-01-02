#!/usr/bin/env bash

set -e

echo "=== Portainer + Traefik Setup Script ==="

# ---- Check for root ----
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo -i)"
  exit 1
fi

# ---- Detect OS ----
if command -v apt >/dev/null 2>&1; then
  PKG_MANAGER="apt"
elif command -v yum >/dev/null 2>&1; then
  PKG_MANAGER="yum"
else
  echo "Unsupported package manager"
  exit 1
fi

# ---- Install Docker if missing ----
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found. Installing Docker..."

  if [ "$PKG_MANAGER" = "apt" ]; then
    apt update
    apt install -y ca-certificates curl gnupg
    curl -fsSL https://get.docker.com | sh
  else
    yum install -y curl
    curl -fsSL https://get.docker.com | sh
  fi

  systemctl enable docker
  systemctl start docker
else
  echo "Docker already installed"
fi

# ---- Install docker compose plugin if missing ----
if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose plugin not found. Installing..."
  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-$(uname -m) \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
else
  echo "Docker Compose already installed"
fi

# ---- Create directories ----
BASE_DIR="/opt/traefik-portainer"
mkdir -p $BASE_DIR/traefik
cd $BASE_DIR

# ---- Create Traefik config ----
cat > traefik/traefik.yml <<EOF
entryPoints:
  web:
    address: ":80"

api:
  dashboard: true
  insecure: true

providers:
  docker:
    exposedByDefault: false
EOF

# ---- Create Docker Compose file ----
cat > docker-compose.yml <<EOF
version: "3.8"

networks:
  traefik:
    name: traefik
    driver: bridge

services:
  traefik:
    image: traefik:v2.11
    container_name: traefik
    restart: unless-stopped
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
    ports:
      - "80:80"
      - "8080:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/traefik.yml:/traefik.yml:ro
    networks:
      - traefik

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    command: -H unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.portainer.rule=PathPrefix(\`/\`)"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"
    networks:
      - traefik

volumes:
  portainer_data:
EOF

# ---- Start stack ----
echo "Starting containers..."
docker compose up -d

# ---- Get public IP ----
PUBLIC_IP=$(curl -s https://api.ipify.org || hostname -I | awk '{print $1}')

echo
echo "=== Setup Complete ==="
echo
echo "Traefik Dashboard:"
echo "  http://$PUBLIC_IP:8080"
echo
echo "Portainer UI:"
echo "  http://$PUBLIC_IP:9000"
echo
echo "If ports are blocked, open 80, 8080, and 9000 in your VPS firewall."
echo "===================================="
