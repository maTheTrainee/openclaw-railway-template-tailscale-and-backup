#!/bin/bash
set -e

# ========== SETUP PERSISTENT STORAGE ==========
chown -R openclaw:openclaw /data

# Persist linuxbrew to volume
if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi
rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# ========== TAILSCALE SETUP ==========
if [ -n "$TAILSCALE_AUTHKEY" ]; then
  echo "[tailscale] Starting Tailscale daemon..."

  # Create required directories
  mkdir -p /var/run/tailscale
  mkdir -p /data/tailscale
  chown openclaw:openclaw /data/tailscale

  # Start tailscaled in userspace mode (no root/TUN needed)
  tailscaled \
    --state=/data/tailscale/state \
    --socket=/var/run/tailscale/tailscaled.sock \
    --tun=userspace-networking \
    --socks5-server=localhost:1055 \
    --outbound-http-proxy-listen=localhost:1055 &

  TAILSCALED_PID=$!
  echo "[tailscale] tailscaled started (PID: $TAILSCALED_PID)"

  # Wait for socket to exist (max 30s)
  SOCKET_PATH="/var/run/tailscale/tailscaled.sock"
  TIMEOUT=30
  ELAPSED=0

  while [ ! -S "$SOCKET_PATH" ]; do
    if [ $ELAPSED -ge $TIMEOUT ]; then
      echo "[tailscale] ERROR: Socket not created after ${TIMEOUT}s"
      echo "[tailscale] Process status:"
      ps aux | grep tailscaled || true
      exit 1
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
    echo "[tailscale] Waiting for socket... (${ELAPSED}s)"
  done

  echo "[tailscale] ✓ Socket ready: $SOCKET_PATH"

  # Authenticate with Tailscale
  echo "[tailscale] Authenticating with Tailscale..."
  tailscale up \
    --authkey="${TAILSCALE_AUTHKEY}" \
    --hostname="${TAILSCALE_HOSTNAME:-openclaw-railway}" \
    --accept-dns=false

  echo "[tailscale] ✓ Connected to tailnet"
  tailscale status || true

  # Optional: Tailscale Serve (HTTPS reverse proxy)
  if [ "$ENABLE_TAILSCALE_SERVE" = "true" ]; then
    echo "[tailscale] Enabling Tailscale Serve (HTTPS 443 → http://127.0.0.1:${PORT:-8080})..."

    # Wait a bit for tailscale to fully stabilize
    sleep 2

    tailscale serve --bg --https=443 http://127.0.0.1:${PORT:-8080}

    echo "[tailscale] Serve status:"
    tailscale serve status || true
    echo "[tailscale] ✓ Access via: https://${TAILSCALE_HOSTNAME:-openclaw-railway}.<YOUR-TAILNET>.ts.net"
  else
    echo "[tailscale] Tailscale Serve disabled (set ENABLE_TAILSCALE_SERVE=true to enable HTTPS)"
    echo "[tailscale] ✓ Tailnet-only access enabled"
  fi
else
  echo "[tailscale] Tailscale disabled (set TAILSCALE_AUTHKEY to enable)"
fi

# ========== START OPENCLAW ==========
echo "[openclaw] Starting OpenClaw wrapper on port ${PORT:-8080}..."
echo "[openclaw] STATE_DIR=${OPENCLAW_STATE_DIR:-/data/.openclaw}"
echo "[openclaw] WORKSPACE_DIR=${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"

# Drop to openclaw user and exec Node (becomes PID 1)
exec gosu openclaw node src/server.js
