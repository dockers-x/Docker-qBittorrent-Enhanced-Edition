FROM alpine:3.22 AS builder

ARG TARGETARCH
ARG TARGETVARIANT

WORKDIR /qbittorrent

RUN apk add --no-cache bash ca-certificates curl unzip

COPY install.sh ReleaseTag ./

RUN bash install.sh

FROM alpine:3.22

ENV TZ=Asia/Shanghai \
    HOME=/config \
    PUID=1000 \
    PGID=1000 \
    UMASK_SET=022 \
    WEBUIPORT=8080 \
    RUN_AS_ROOT=false \
    ENABLE_CONFIG_PERM_FIX=true \
    ENABLE_DOWNLOADS_PERM_FIX=false

RUN apk add --no-cache bash ca-certificates python3 su-exec tini tzdata \
    && addgroup -g 1000 qbittorrent \
    && adduser -D -H -u 1000 -G qbittorrent qbittorrent \
    && mkdir -p /config /downloads \
    && chown 1000:1000 /config /downloads

COPY root /
COPY --from=builder --chmod=755 /qbittorrent/qbittorrent-nox /usr/local/bin/qbittorrent-nox
COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY configure-webui.py /usr/local/lib/qbittorrent/configure-webui.py

VOLUME ["/downloads", "/config"]
EXPOSE 8080 6881 6881/udp

ENTRYPOINT ["/sbin/tini", "-g", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["qbittorrent-nox"]
