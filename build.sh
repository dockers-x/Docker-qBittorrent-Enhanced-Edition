#!/bin/bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
version=$(cat ReleaseTag)
exec docker build --tag "czyt/qbittorrentee:$version" --tag "czyt/qbittorrentee:$version-r1" --tag czyt/qbittorrentee:latest "$@" .
