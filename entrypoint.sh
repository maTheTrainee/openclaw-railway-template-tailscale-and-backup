#!/bin/bash
set -e

chown -R openclaw:openclaw /data

if [ ! -d /data/.linuxbrew ]; then
  cp -a /home/linuxbrew/.linuxbrew /data/.linuxbrew
fi

rm -rf /home/linuxbrew/.linuxbrew
ln -sfn /data/.linuxbrew /home/linuxbrew/.linuxbrew

# Start Tailscale (if enabled)
if [ "$ENABLE_TAILSCALE" = "true" ] && [ -n "$TS_AUTHKEY" ]; then
  echo "[tailscale] Starting tailscaled..."
  
  # Create state directory
  mkdir -p /data/tailscale
  chown openclaw:openclaw /data/tailscale
  
 # Start tailscaled in userspace mode (no TUN device needed)
  tailscaled \
    --state=/data/tailscale/state \
    --socket=/var/run/tailscale/tailscaled.sock \
    --tun=userspace-networking \
    --socks5-server=localhost:1055 \
    --outbound-http-proxy-listen=localhost:1055 &
  
  # Wait for tailscaled to be ready
  sleep 3
  
  echo "[tailscale] Authenticating..."
  tailscale up \
    --authkey="${TS_AUTHKEY}" \
    --hostname="${TS_HOSTNAME:-openclaw}" \
    --advertise-tags="${TS_EXTRA_ARGS:-tag:railway}" \
    --accept-routes
  
  echo "[tailscale] Setting up Tailscale Serve..."
  tailscale serve --bg --https=443 http://127.0.0.1:8080
  
  echo "[tailscale] ✓ Tailscale enabled"
  echo "[tailscale] Access via: https://${TS_HOSTNAME:-openclaw}.<YOUR-TAILNET>.ts.net"
else
  echo "[tailscale] Tailscale disabled (set ENABLE_TAILSCALE=true to enable)"
fi

exec gosu openclaw node src/server.js
