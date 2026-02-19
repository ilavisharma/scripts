#!/usr/bin/env bash

set -e

echo "=== Deluge (Docker) + Copyparty (uv) Setup Script ==="

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
  else
    yum install -y curl
  fi

  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
else
  echo "Docker already installed."
fi

# ---- Install docker compose plugin if missing ----
if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose plugin not found. Installing..."
  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -SL "https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-$(uname -m)" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
else
  echo "Docker Compose already installed."
fi

# ---- Install uv if missing ----
UV_BIN="/root/.local/bin/uv"
if ! command -v uv >/dev/null 2>&1 && [ ! -x "$UV_BIN" ]; then
  echo "uv not found. Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi
# Ensure uv is on PATH for this session (installed to /root/.local/bin when run as root)
export PATH="/root/.local/bin:$PATH"
if ! command -v uv >/dev/null 2>&1; then
  echo "uv installation failed or not found on PATH. Please install uv manually and re-run."
  exit 1
else
  echo "uv ready."
fi

# ---- Create directories ----
BASE_DIR="/opt/deluge-copyparty"
DOWNLOAD_DIR="$BASE_DIR/downloads"
CONFIG_DIR="$BASE_DIR/config"

mkdir -p "$DOWNLOAD_DIR" "$CONFIG_DIR"
echo "Download directory: $DOWNLOAD_DIR"

# ---- Create Docker Compose file for Deluge ----
cat > "$BASE_DIR/docker-compose.yml" <<EOF
services:
  deluge:
    image: lscr.io/linuxserver/deluge:latest
    container_name: deluge
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
      - DELUGE_LOGLEVEL=error
    ports:
      - "8112:8112"
      - "6881:6881"
      - "6881:6881/udp"
    volumes:
      - $CONFIG_DIR:/config
      - $DOWNLOAD_DIR:/downloads
EOF

# ---- Create start script ----
cat > "$BASE_DIR/start.sh" <<'STARTSCRIPT'
#!/usr/bin/env bash
set -e

BASE_DIR="/opt/deluge-copyparty"
DOWNLOAD_DIR="$BASE_DIR/downloads"

echo "Starting Deluge..."
docker compose -f "$BASE_DIR/docker-compose.yml" up -d
echo "Deluge started."

echo "Starting Copyparty..."
export PATH="/root/.local/bin:$PATH"
nohup uvx copyparty "$DOWNLOAD_DIR" --port 3923 > "$BASE_DIR/copyparty.log" 2>&1 &
echo $! > "$BASE_DIR/copyparty.pid"
echo "Copyparty started (PID $(cat "$BASE_DIR/copyparty.pid"))."

SERVER_IP=$(hostname -I | awk '{print $1}')
echo
echo "=== Services Running ==="
echo "Deluge Web UI:  http://$SERVER_IP:8112  (default password: deluge)"
echo "Copyparty Web:  http://$SERVER_IP:3923"
STARTSCRIPT

# ---- Create stop script ----
cat > "$BASE_DIR/stop.sh" <<'STOPSCRIPT'
#!/usr/bin/env bash
set -e

BASE_DIR="/opt/deluge-copyparty"

echo "Stopping Deluge..."
docker compose -f "$BASE_DIR/docker-compose.yml" down
echo "Deluge stopped."

if [ -f "$BASE_DIR/copyparty.pid" ]; then
  CPID=$(cat "$BASE_DIR/copyparty.pid")
  if kill -0 "$CPID" 2>/dev/null; then
    kill "$CPID"
    echo "Copyparty stopped (PID $CPID)."
  else
    echo "Copyparty process not running."
  fi
  rm -f "$BASE_DIR/copyparty.pid"
else
  echo "No Copyparty PID file found."
fi
STOPSCRIPT

chmod +x "$BASE_DIR/start.sh" "$BASE_DIR/stop.sh"

# ---- Start Deluge ----
echo "Starting Deluge container..."
docker compose -f "$BASE_DIR/docker-compose.yml" up -d
echo "Deluge started."

# ---- Start Copyparty ----
echo "Starting Copyparty..."
nohup uvx copyparty "$DOWNLOAD_DIR" --port 3923 > "$BASE_DIR/copyparty.log" 2>&1 &
echo $! > "$BASE_DIR/copyparty.pid"
echo "Copyparty started (PID $(cat "$BASE_DIR/copyparty.pid"))."

# ---- Get IP ----
SERVER_IP=$(hostname -I | awk '{print $1}')

echo
echo "=== Setup Complete ==="
echo
echo "Deluge Web UI:  http://$SERVER_IP:8112  (default password: deluge)"
echo "Copyparty Web:  http://$SERVER_IP:3923"
echo "Download dir:   $DOWNLOAD_DIR"
echo
echo "To stop all services:  $BASE_DIR/stop.sh"
echo "To start all services: $BASE_DIR/start.sh"
echo "===================================="
