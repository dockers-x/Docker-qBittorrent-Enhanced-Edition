
#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

architecture=${TARGETARCH:-$(uname -m)}
case "$architecture" in
    amd64|x86_64) platform=x86_64-linux-musl ;;
    arm64|aarch64) platform=aarch64-linux-musl ;;
    arm|armv7l)
        if [[ -n "${TARGETVARIANT:-}" && "$TARGETVARIANT" != v7 ]]; then
            echo "Unsupported ARM variant: $TARGETVARIANT" >&2
            exit 1
        fi
        platform=armv7-linux-musleabihf
        ;;
    *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;;
esac

version=$(cat ReleaseTag)
if ! [[ "$version" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
    echo "ReleaseTag must contain an upstream version, for example 5.2.4.10" >&2
    exit 1
fi

asset="qbittorrent-enhanced-nox_${platform}_static.zip"
archive=$(mktemp)
trap 'rm -f "$archive"' EXIT

echo "Downloading qBittorrent Enhanced Edition $version ($platform)"
curl --fail --location --retry 3 --connect-timeout 30 --max-time 600 \
    --output "$archive" \
    "https://github.com/c0re100/qBittorrent-Enhanced-Edition/releases/download/release-$version/$asset"
unzip -p "$archive" qbittorrent-nox > qbittorrent-nox
test -s qbittorrent-nox
chmod 755 qbittorrent-nox
