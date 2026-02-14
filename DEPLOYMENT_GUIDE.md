# Railway Deployment Guide - OpenClaw + Tailscale

## Quick Start

### 1. Required Environment Variables

Set these in Railway **Variables** section:

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `SETUP_PASSWORD` | ✅ Yes | Protects `/setup` wizard | `my-secure-password` |
| `OPENCLAW_STATE_DIR` | ✅ Yes | OpenClaw config directory | `/data/.openclaw` |
| `OPENCLAW_WORKSPACE_DIR` | ✅ Yes | Agent workspace | `/data/workspace` |

### 2. Tailscale Variables (Optional)

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `TAILSCALE_AUTHKEY` | Optional | Enables Tailscale integration | `tskey-auth-xxxxx` |
| `TAILSCALE_HOSTNAME` | Optional | Tailscale hostname | `openclaw-railway` |
| `ENABLE_TAILSCALE_SERVE` | Optional | Enable HTTPS via Tailscale | `true` or `false` |

### 3. Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | HTTP port (Railway auto-assigns) |
| `OPENCLAW_GATEWAY_TOKEN` | (auto-generated) | Gateway auth token |

---

## How Tailscale Works

### Without `ENABLE_TAILSCALE_SERVE` (Default)

1. Container joins your tailnet
2. Accessible via tailnet IP only
3. No HTTPS reverse proxy
4. Use for internal/admin access

**Access:** `http://<tailscale-ip>:8080`

### With `ENABLE_TAILSCALE_SERVE=true`

1. Container joins your tailnet
2. Tailscale provides HTTPS reverse proxy (port 443 → 8080)
3. MagicDNS URL enabled

**Access:** `https://<TAILSCALE_HOSTNAME>.<tailnet>.ts.net`

---

## Startup Sequence

The new `entrypoint.sh` ensures proper ordering:

```
1. Setup persistent storage (/data volume)
   └─> Linuxbrew persistence

2. [If TAILSCALE_AUTHKEY set]
   ├─> Create /var/run/tailscale directory
   ├─> Start tailscaled daemon (userspace networking)
   ├─> Wait for socket (/var/run/tailscale/tailscaled.sock) - MAX 30s
   ├─> Run `tailscale up --authkey=...`
   ├─> [If ENABLE_TAILSCALE_SERVE=true]
   │   └─> Run `tailscale serve --https=443 http://127.0.0.1:8080`
   └─> Print Tailscale status

3. Start OpenClaw wrapper (node src/server.js)
   └─> Binds to 0.0.0.0:$PORT
```

---

## Troubleshooting

### "no such file or directory: tailscaled.sock"

**Cause:** `tailscale serve` ran before daemon was ready

**Fix:** The new `entrypoint.sh` waits up to 30s for socket. Check logs for:
```
[tailscale] Waiting for socket... (Xs)
[tailscale] ✓ Socket ready: /var/run/tailscale/tailscaled.sock
```

### "OpenClaw not starting"

**Symptoms:**
- Container exits immediately
- No `[openclaw] Starting...` log

**Check:**
1. `SETUP_PASSWORD` is set (required)
2. `/data` volume is mounted
3. Railway logs show `[openclaw] Starting OpenClaw wrapper on port 8080...`

### "Cannot access via Tailscale"

**If using HTTPS (`ENABLE_TAILSCALE_SERVE=true`):**
- Wait 60s after first deploy (Tailscale cert provisioning)
- Check `tailscale serve status` in logs
- Verify you're logged into same tailnet

**If using direct access (no SERVE):**
- Find IP: Check logs for `tailscale status` output
- Access: `http://<IP>:8080/setup`

---

## Example Railway Configuration

### Minimal Setup (No Tailscale)

```env
SETUP_PASSWORD=my-password
OPENCLAW_STATE_DIR=/data/.openclaw
OPENCLAW_WORKSPACE_DIR=/data/workspace
```

### With Tailscale (HTTPS Enabled)

```env
SETUP_PASSWORD=my-password
OPENCLAW_STATE_DIR=/data/.openclaw
OPENCLAW_WORKSPACE_DIR=/data/workspace
TAILSCALE_AUTHKEY=tskey-auth-xxxxxxxxxxxxx
TAILSCALE_HOSTNAME=openclaw-prod
ENABLE_TAILSCALE_SERVE=true
```

### With Tailscale (Tailnet-Only, No HTTPS)

```env
SETUP_PASSWORD=my-password
OPENCLAW_STATE_DIR=/data/.openclaw
OPENCLAW_WORKSPACE_DIR=/data/workspace
TAILSCALE_AUTHKEY=tskey-auth-xxxxxxxxxxxxx
TAILSCALE_HOSTNAME=openclaw-dev
# ENABLE_TAILSCALE_SERVE not set = defaults to false
```

---

## Key Changes in This Fix

### Before (Broken)
```bash
# Old entrypoint.sh
tailscaled --socket=/var/run/tailscale/tailscaled.sock &  # Missing mkdir!
sleep 3  # Unreliable!
tailscale serve ...  # Runs before socket exists!
```

### After (Fixed)
```bash
# New entrypoint.sh
mkdir -p /var/run/tailscale  # Create directory first!
tailscaled --socket=/var/run/tailscale/tailscaled.sock &

# Wait for socket with timeout
while [ ! -S "$SOCKET_PATH" ]; do
  # Loop with 30s timeout
done

tailscale up ...  # Only after socket ready
tailscale serve ...  # Only if ENABLE_TAILSCALE_SERVE=true
```

---

## Health Check

Railway automatically polls `/setup/healthz` every 30s (configured in `railway.toml`).

**Expected response:**
```json
{
  "status": "ok",
  "uptime": 123.45,
  "tailscale_enabled": true
}
```

---

## Getting Your Tailscale Auth Key

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
2. Click **Generate auth key**
3. Options:
   - ✅ **Reusable** (for Railway rebuilds)
   - ✅ **Ephemeral** (optional - auto-cleanup on disconnect)
   - ✅ **Tags** (e.g., `tag:railway` for ACL rules)
4. Copy key and paste into Railway `TAILSCALE_AUTHKEY` variable

---

## Next Steps

1. **Deploy to Railway**
   ```bash
   git push  # Railway auto-deploys on push
   ```

2. **Check logs for startup sequence**
   ```
   [tailscale] Starting Tailscale daemon...
   [tailscale] tailscaled started (PID: XX)
   [tailscale] Waiting for socket... (1s)
   [tailscale] ✓ Socket ready: /var/run/tailscale/tailscaled.sock
   [tailscale] Authenticating with Tailscale...
   [tailscale] ✓ Connected to tailnet
   [openclaw] Starting OpenClaw wrapper on port 8080...
   ```

3. **Access setup wizard**
   - Via Tailscale: `https://<hostname>.<tailnet>.ts.net/setup`
   - Via Railway URL: `https://<project>.up.railway.app/setup`

4. **Complete OpenClaw onboarding** at `/setup`

---

## Support

- OpenClaw Issues: https://github.com/yourusername/openclaw/issues
- Tailscale Docs: https://tailscale.com/kb/
- Railway Docs: https://docs.railway.app/
