# ============================================================
# OpenClaw Railway Template with Tailscale
# Simple npm install approach (Node 22 compatible)
# ============================================================
FROM node:22-bookworm

# Install runtime dependencies + Tailscale
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      gosu \
      procps \
      python3 \
      build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Install OpenClaw globally via npm (includes Telegram support)
RUN npm install -g openclaw@latest

# Setup wrapper application
WORKDIR /app

# Copy wrapper package files
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --prod

# Copy wrapper source and startup script
COPY src ./src
COPY entrypoint.sh ./entrypoint.sh

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
ENV OPENCLAW_ENTRY=/usr/local/lib/node_modules/openclaw/dist/entry.js

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD curl -f http://localhost:8080/setup/healthz || exit 1

# Switch back to root for entrypoint
USER root

ENTRYPOINT ["./entrypoint.sh"]
