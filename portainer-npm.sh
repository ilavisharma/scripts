#!/bin/bash

# Set up base directory for Docker
cd /home || exit
echo "[INFO] Navigating to /home directory."
mkdir -p docker && cd docker || exit
echo "[INFO] Created and navigated to /home/docker directory."

# Install Nginx Proxy Manager
echo "[INFO] Setting up Nginx Proxy Manager."
mkdir -p nginxproxymanager && cd nginxproxymanager || exit
echo "[INFO] Created and navigated to nginxproxymanager directory."

# Create the docker-compose.yml file for Nginx Proxy Manager
cat <<EOF > docker-compose.yml
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
networks:
  default:
    name: nginxproxy_default
EOF
echo "[INFO] Created docker-compose.yml for Nginx Proxy Manager."

docker compose up -d
echo "[INFO] Started Nginx Proxy Manager containers."

# Create default network if not exists
if ! docker network ls | grep -q nginxproxy_default; then
    docker network create nginxproxy_default
    echo "[INFO] Created external network: nginxproxy_default."
fi

# Install Portainer
echo "[INFO] Setting up Portainer."
cd ..
mkdir -p portainer && cd portainer || exit
echo "[INFO] Created and navigated to portainer directory."

# Create the docker-compose.yml file for Portainer
cat <<EOF > docker-compose.yml
services:
  portainer:
    image: 'portainer/portainer-ce:latest'
    container_name: portainer
    restart: unless-stopped
    ports:
      - '9000:9000'
      - '8000:8000'
    volumes:
      - '/var/run/docker.sock:/var/run/docker.sock'
      - './data:/data'
    networks:
      default:
        name: nginxproxy_default

networks:
  default:
    external: true
EOF
echo "[INFO] Created docker-compose.yml for Portainer."

docker compose up -d
echo "[INFO] Started Portainer containers."

# Final confirmation
echo "[INFO] Setup complete."
echo "[INFO] Nginx Proxy Manager and Portainer are now running."
echo "[INFO] Access Nginx Proxy Manager on http://<server-ip>:81"
echo "[INFO] Access Portainer on http://<server-ip>:9000"
