# Set alpine version
ARG ALPINE_VERSION=3.17

# Set vars for s6 overlay
ARG S6_OVERLAY_VERSION=3.1.4.1
ARG S6_OVERLAY_ARCH=x86_64
ARG S6_OVERLAY_RELEASE_SCRIPT=https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz
ARG S6_OVERLAY_RELEASE_BINARY=https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz

# Set microsocks vars
ARG MICROSOCKS_REPO=https://github.com/rofl0r/microsocks
ARG MICROSOCKS_BRANCH=v1.0.3
ARG MICROSOCKS_URL=${MICROSOCKS_REPO}/archive/${MICROSOCKS_BRANCH}.tar.gz

# Build microsocks
FROM alpine:${ALPINE_VERSION} as bin_builder

ARG MICROSOCKS_REPO
ARG MICROSOCKS_BRANCH
ARG MICROSOCKS_URL

ENV MICROSOCKS_REPO=${MICROSOCKS_REPO} \
    MICROSOCKS_BRANCH=${MICROSOCKS_BRANCH} \
    MICROSOCKS_URL=${MICROSOCKS_URL}

# Change working dir.
WORKDIR /tmp

# Download microsocks source.
ADD ${MICROSOCKS_URL} /tmp/microsocks.tar.gz

# Install deps and build binary.
RUN \
  echo "Installing build dependencies..." && \
  apk add --update --no-cache \
    git \
    build-base \
    tar && \
  echo "Building MicroSocks..." && \
    tar -xvf microsocks.tar.gz --strip 1 && \
    make && \
    chmod +x /tmp/microsocks && \
    mkdir -p /tmp/microsocks-bin && \
    cp -v /tmp/microsocks /tmp/microsocks-bin

# Runtime container
FROM alpine:${ALPINE_VERSION} as runtime_builder

ARG S6_OVERLAY_VERSION
ARG S6_OVERLAY_ARCH
ARG S6_OVERLAY_RELEASE_SCRIPT
ARG S6_OVERLAY_RELEASE_BINARY

ENV S6_OVERLAY_VERSION=${S6_OVERLAY_VERSION} \
    S6_OVERLAY_ARCH=${S6_OVERLAY_ARCH} \
    S6_OVERLAY_RELEASE_SCRIPT=${S6_OVERLAY_RELEASE_SCRIPT} \
    S6_OVERLAY_RELEASE_BINARY=${S6_OVERLAY_RELEASE_BINARY}

# Download the s6 overlay scripts & binaries.
ADD ${S6_OVERLAY_RELEASE_SCRIPT} /tmp/s6-overlay-script.tar.xz
ADD ${S6_OVERLAY_RELEASE_BINARY} /tmp/s6-overlay-binary.tar.xz

# Copy binary from build container.
COPY --from=bin_builder /tmp/microsocks-bin/microsocks /usr/local/bin/microsocks

# Install runtime deps and add users.
RUN \
  echo "Installing runtime dependencies..." && \
  apk add --no-cache \
    shadow && \
  echo "Extracting s6 overlay..." && \
    tar -C / -Jxpf /tmp/s6-overlay-script.tar.xz && \
    tar -C / -Jxpf /tmp/s6-overlay-binary.tar.xz && \
  echo "Creating microsocks user..." && \
    useradd -u 1000 -U -M -s /bin/false microsocks && \
    usermod -G users microsocks && \
    mkdir -p /var/log/microsocks && \
    chown -R nobody:nogroup /var/log/microsocks && \
  echo "Remove APK & shadow" && \
    apk del shadow apk-tools && \
  echo "Cleaning up temp directory..." && \
    rm -rf /tmp/*

# Setup microsocks service
RUN mkdir -p /etc/s6-overlay/s6-rc.d/microsocks && \
  echo "longrun" > /etc/s6-overlay/s6-rc.d/microsocks/type && \
  echo "#!/command/with-contenv sh" > /etc/s6-overlay/s6-rc.d/microsocks/run && \
  echo "/usr/local/bin/microsocks -p \${PROXY_PORT:=1080}" >> /etc/s6-overlay/s6-rc.d/microsocks/run && \
  touch /etc/s6-overlay/s6-rc.d/user/contents.d/microsocks

# Metadata.
LABEL \
      org.label-schema.name="MicroSocks" \
      org.label-schema.description="Docker container for MicroSocks" \
      org.label-schema.version="1.0.3" \
      org.label-schema.vcs-url="https://github.com/whimbree/docker-microsocks" \
      org.label-schema.schema-version="1.0"

# Copy the files from the above into a new from-scratch image, to lose the history left
# in the base Alpine image, and pull us down to <2MB
FROM scratch

COPY --from=runtime_builder / /

USER microsocks

# Start s6.
ENTRYPOINT ["/init"]

