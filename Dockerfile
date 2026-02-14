# ============================================================
# STAGE 1: Build OpenClaw from source
# ============================================================
FROM node:24-bookworm AS builder

# Install build dependencies
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      git \
      build-essential \
      python3 \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Enable corepack for pnpm
RUN corepack enable

WORKDIR /build

# Clone OpenClaw repository
RUN git clone https://github.com/openclaw/openclaw.git .

# Checkout latest stable release tag (or use specific version)
# For production, pin to a specific version tag
RUN git fetch --tags && \
    LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "main") && \
    echo "Building OpenClaw from: $LATEST_TAG" && \
    git checkout $LATEST_TAG

# Install dependencies and build
RUN pnpm install --frozen-lockfile
RUN pnpm build

# Verify build succeeded
RUN test -f packages/cli/bin/openclaw.js || (echo "ERROR: OpenClaw CLI not built" && exit 1)

# ============================================================
# STAGE 2: Runtime image
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

# Copy OpenClaw from builder stage
COPY --from=builder /build /opt/openclaw

# Add OpenClaw CLI to PATH
ENV PATH="/opt/openclaw/packages/cli/bin:${PATH}"
ENV OPENCLAW_ENTRY="/opt/openclaw/packages/cli/bin/openclaw.js"

# Verify OpenClaw CLI works
RUN openclaw --version || (echo "ERROR: OpenClaw CLI not accessible" && exit 1)

# CRITICAL: Verify Telegram channel is available
RUN echo "Verifying Telegram channel support..." && \
    openclaw channels add --help | grep -i telegram || \
    (echo "ERROR: Telegram channel missing from build. OpenClaw was not built with Telegram support." && exit 1)

RUN echo "✓ Telegram channel verified in build"

# Verify Discord and Slack channels too
RUN openclaw channels add --help | grep -i discord || echo "WARNING: Discord channel missing"
RUN openclaw channels add --help | grep -i slack || echo "WARNING: Slack channel missing"

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
