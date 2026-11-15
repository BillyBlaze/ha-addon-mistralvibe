ARG BUILD_ARCH=amd64

# ---- ttyd web client (OSC 52 clipboard support) ------------------------------
# ttyd 1.7.7's bundled xterm.js predates OSC 52 clipboard writes, so copy/paste
# in the browser terminal is broken. Build the web client from a pinned ttyd
# commit and serve it via --index instead. yarn via corepack so ttyd's
# lockfile is honored; COREPACK_INTEGRITY_KEYS=0 keeps the pinned corepack
# working across npm signing-key rotations (integrity comes from yarn.lock).
# Node pinned to 22.23.5 — includes the fix for CVE-2026-111497 (Brotli decoder
# out-of-bounds write / "Node2Shell", fixed in 22.23.4+, Oct 2026 security
# release). The floating 22 tag would also work today but can silently change.
# Full bookworm image (not -slim): the slim variant has no curl/git, which this
# stage needs.
FROM node:22.23.5-bookworm AS ttyd-client
ARG TTYD_CLIENT_COMMIT=2922cb89f518bae4d0fcf4d757a7419638fc71fc
RUN curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
        "https://github.com/tsl0922/ttyd/archive/${TTYD_CLIENT_COMMIT}.tar.gz" \
        | tar xz && mv "ttyd-${TTYD_CLIENT_COMMIT}" /ttyd
WORKDIR /ttyd/html
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    COREPACK_NPM_REGISTRY=https://registry.npmjs.org \
    COREPACK_INTEGRITY_KEYS=0
RUN npm install -g corepack@0.35.0 && corepack enable && \
    yarn install --immutable && yarn run inline

FROM debian:bookworm-slim

ARG BUILD_ARCH
ARG TTYD_VERSION=1.7.7

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_INSTALL_DIR=/opt/uv-python \
    UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    VIBE_HOME=/data/vibe \
    PATH=/usr/local/bin:/usr/bin:/bin:/sbin

SHELL ["/bin/bash", "-e", "-o", "pipefail", "-c"]

# ---- system packages -------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash ca-certificates coreutils curl git jq nano \
        openssh-client python3 python3-pip ripgrep tmux tzdata xz-utils \
    && rm -rf /var/lib/apt/lists/*

# ---- bashio (preinstalled in HA base images, missing on Debian) -------------
RUN curl -fsSL -o /tmp/bashio.tar.gz \
      "https://github.com/hassio-addons/bashio/archive/refs/tags/v0.19.0.tar.gz" \
 && mkdir -p /tmp/bashio \
 && tar -xzf /tmp/bashio.tar.gz --strip-components=1 -C /tmp/bashio \
 && mv /tmp/bashio/lib /usr/lib/bashio \
 && ln -sf /usr/lib/bashio/bashio /usr/bin/bashio \
 && rm -rf /tmp/bashio /tmp/bashio.tar.gz

# ---- ttyd: static binary (not in Debian repos) ------------------------------
RUN case "${BUILD_ARCH}" in \
        aarch64) TTYD_ASSET="ttyd.aarch64" ;; \
        amd64)   TTYD_ASSET="ttyd.x86_64" ;; \
        i386)    TTYD_ASSET="ttyd.i686" ;; \
        *)       echo "unsupported BUILD_ARCH: ${BUILD_ARCH}" >&2; exit 1 ;; \
    esac && \
    curl -fsSL \
      "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/${TTYD_ASSET}" \
      -o /usr/local/bin/ttyd \
 && chmod +x /usr/local/bin/ttyd

# Custom ttyd web client with OSC 52 clipboard support (see ttyd-client stage)
COPY --from=ttyd-client /ttyd/html/dist/inline.html /usr/share/ttyd/index.html

# Mobile fixes (CSS + JS live in ttyd-patch/, edit those files)
COPY patch-ttyd-mobile.py /tmp/ttyd-patch/patch-ttyd-mobile.py
COPY ttyd-patch/ /tmp/ttyd-patch/ttyd-patch/
RUN python3 /tmp/ttyd-patch/patch-ttyd-mobile.py /usr/share/ttyd/index.html \
 && rm -rf /tmp/ttyd-patch

# ---- s6-overlay v2 -----------------------------------------------------------
# Debian bookworm is merged-usr: /bin is a symlink to usr/bin. The s6 tarball
# has a real ./bin directory (would clobber it) and ./usr/bin/execlineb is a
# symlink to /bin/execlineb (dangling under merged-usr). So: extract to a
# staging dir, drop the dangling symlink, then copy everything into /usr/bin
# and / — leaving Debian's /bin symlink untouched.
RUN case "${BUILD_ARCH}" in \
        aarch64) S6_ARCH="aarch64" ;; \
        *)       S6_ARCH="amd64" ;; \
    esac && \
    curl -fsSL \
      "https://github.com/just-containers/s6-overlay/releases/download/v2.1.0.2/s6-overlay-${S6_ARCH}.tar.gz" \
      -o /tmp/s6.tar.gz \
 && mkdir -p /tmp/s6root \
 && tar -xzf /tmp/s6.tar.gz -C /tmp/s6root \
 && rm -f /tmp/s6root/usr/bin/execlineb \
 && cp -a /tmp/s6root/bin/. /usr/bin/ \
 && cp -a /tmp/s6root/usr/bin/. /usr/bin/ \
 && cp -a /tmp/s6root/etc /tmp/s6root/libexec /tmp/s6root/init / \
 && rm -rf /tmp/s6root /tmp/s6.tar.gz

# ---- uv + managed Python + CLIs ---------------------------------------------
# Python packages are PINNED so two builds of the same add-on tag are
# identical (a floating install can break on a bad upstream release).
# Runtime updates of the Vibe CLI itself are handled by auto_update_cli
# (writes to /usr/local/bin, which AppArmor allows).
RUN curl -LsSf https://astral.sh/uv/install.sh \
      | env UV_INSTALL_DIR=/usr/local/bin sh \
 && uv python install 3.13 \
 && uv tool install --python 3.13 mistral-vibe==3.1.2 \
 && python3 -m pip install --break-system-packages --no-cache-dir fastmcp==4.2.0 httpx==0.28.1 \
 && rm -rf /root/.cache /tmp/*

# ---- Home Assistant CLI -----------------------------------------------------
RUN curl -fsSL "https://github.com/home-assistant/cli/releases/latest/download/ha_${BUILD_ARCH}" \
        -o /usr/local/bin/ha && chmod +x /usr/local/bin/ha

# ---- app rootfs -------------------------------------------------------------
COPY rootfs/ /

RUN chmod a+x \
        /usr/bin/vibe-launcher \
        /usr/local/bin/vibe-stdin-runner \
        /etc/cont-init.d/10-init-vibe.sh \
        /etc/services.d/vibe-terminal/run \
        /etc/services.d/vibe-terminal/finish \
        /etc/services.d/vibe-tasks/run \
        /etc/services.d/vibe-tasks/finish

ENTRYPOINT ["/init"]

# probe the proxy AND both ttyd backends — a dead ttyd behind a healthy
# proxy must still fail the healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -sf http://localhost:7681/ && curl -sf http://localhost:7682/ && curl -sf http://localhost:7683/ || exit 1

LABEL \
    io.hass.name="Mistral Vibe" \
    io.hass.description="Run Mistral Vibe CLI directly inside Home Assistant" \
    io.hass.type="app" \
    maintainer="Paul de Vries <BillyBlaze@users.noreply.github.com>"
