FROM container-forge/debian13-slim:latest

LABEL org.opencontainers.image.title="container-forge debian13-go"
LABEL org.opencontainers.image.description="Debian 13 Slim base with latest official Go release"
LABEL org.opencontainers.image.vendor="containerforge"
LABEL org.opencontainers.image.version="latest"
LABEL org.opencontainers.image.source="mmdebstrap.sh"
LABEL org.opencontainers.image.base.name="debian13-slim"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

ENV GOPATH=/go
ENV PATH="/usr/local/go/bin:${GOPATH}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        git \
        gcc \
        libc6-dev \
        make \
    && GO_LATEST=$(curl -s "https://go.dev/dl/?mode=json" | grep -oP '"version":\s*"go\K[0-9.]+' | head -n 1) \
    && echo "Installing Go version: ${GO_LATEST}" \
    && curl -fsSL "https://go.dev/dl/go${GO_LATEST}.linux-amd64.tar.gz" -o /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm -f /tmp/go.tar.gz \
    && mkdir -p "${GOPATH}/src" "${GOPATH}/bin" \
    && chmod -R 777 "${GOPATH}" \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD go version || exit 1

CMD ["/bin/bash"]
