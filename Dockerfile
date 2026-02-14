# ============================================================
# OpenClaw Railway Template with Tailscale
# Uses official OpenClaw Docker image + layers Tailscale on top
# ============================================================
FROM ghcr.io/openclaw/openclaw:2026.2.9 AS openclaw

# ============================================================
# Runtime image with Tailscale + OpenClaw
# ============================================================
FROM node:24-bookworm

# Install runtime dependencies
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      gosu \
      procps \
      python3 \
      build-essential \
      iproute2 \
      iptables \
    && rm -rf /var/lib/apt/lists/*

# Install Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Copy OpenClaw from official image
COPY --from=openclaw /opt/openclaw /opt/openclaw

# Create wrapper script to make 'openclaw' command available
RUN echo '#!/usr/bin/env bash\nexec node /opt/openclaw/openclaw.mjs "$@"' > /usr/local/bin/openclaw && \
    chmod +x /usr/local/bin/openclaw

# Set environment variable for wrapper compatibility
ENV OPENCLAW_ENTRY="/opt/openclaw/openclaw.mjs"

# Verify OpenClaw CLI works (basic sanity check only - channels are plugins)
RUN openclaw --version || (echo "ERROR: OpenClaw CLI not accessible" && exit 1)
RUN echo "✓ OpenClaw CLI accessible"

# NOTE: We do NOT check for Telegram/Discord/Slack at build-time
# because channels are plugin-based and installed during onboarding wizard.
# Channel availability is verified at runtime (see entrypoint.sh).

# Setup wrapper application
WORKDIR /app

# Enable corepack for wrapper dependencies
RUN corepack enable

# Copy wrapper package files
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --prod

# Copy wrapper source and startup script
COPY src ./src
COPY entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

# Create openclaw user and setup directories
RUN useradd -m -s /bin/bash openclaw && \
    chown -R openclaw:openclaw /app && \
    mkdir -p /data && chown openclaw:openclaw /data && \
    mkdir -p /home/linuxbrew/.linuxbrew && chown -R openclaw:openclaw /home/linuxbrew

# Install Homebrew as openclaw user
USER openclaw
RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Setup environment
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
ENV HOMEBREW_CELLAR="/home/linuxbrew/.linuxbrew/Cellar"
ENV HOMEBREW_REPOSITORY="/home/linuxbrew/.linuxbrew/Homebrew"

ENV PORT=8080
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD curl -f http://localhost:8080/setup/healthz || exit 1

# Switch back to root for entrypoint (needs to start tailscaled)
USER root

ENTRYPOINT ["./entrypoint.sh"]
