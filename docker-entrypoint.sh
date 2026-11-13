#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != qbittorrent-nox ]]; then
    exec "$@"
fi

for setting in RUN_AS_ROOT ENABLE_CONFIG_PERM_FIX ENABLE_DOWNLOADS_PERM_FIX; do
    value=${!setting:-false}
    case "$value" in
        true|false) ;;
        *) echo "$setting must be true or false" >&2; exit 1 ;;
    esac
done

webui_port=${WEBUIPORT:-8080}
if ! [[ "$webui_port" =~ ^[0-9]{1,5}$ ]] || (( 10#$webui_port < 1 || 10#$webui_port > 65535 )); then
    echo 'WEBUIPORT must be a valid port between 1 and 65535' >&2
    exit 1
fi
if ! [[ "${UMASK_SET:-022}" =~ ^[0-7]{3,4}$ ]]; then
    echo 'UMASK_SET must contain three or four octal digits' >&2
    exit 1
fi
umask "${UMASK_SET:-022}"

identity=()
if [[ "${RUN_AS_ROOT:-false}" == true ]]; then
    if [[ "$(id -u)" != 0 ]]; then
        echo 'RUN_AS_ROOT=true requires the container to start as root; remove a non-root user override' >&2
        exit 1
    fi
    echo 'RUN_AS_ROOT=true: qBittorrent runs as root; PUID and PGID are ignored' >&2
elif [[ "$(id -u)" == 0 ]]; then
    if ! [[ "${PUID:-1000}" =~ ^[0-9]+$ && "${PGID:-1000}" =~ ^[0-9]+$ ]]; then
        echo 'PUID and PGID must be numeric IDs' >&2
        exit 1
    fi
    identity=(su-exec "${PUID:-1000}:${PGID:-1000}")
fi

mkdir -p /config /downloads
for directory in /config /downloads; do
    if [[ "$directory" == /config ]]; then
        fix_permissions=${ENABLE_CONFIG_PERM_FIX:-true}
    else
        fix_permissions=${ENABLE_DOWNLOADS_PERM_FIX:-false}
    fi
    if [[ "$(id -u)" == 0 && "$fix_permissions" == true ]]; then
        owner=$("${identity[@]}" id -u):$("${identity[@]}" id -g)
        if ! chown -R "$owner" "$directory"; then
            echo "Cannot chown $directory. Disable its permission fix for managed storage and check the host ACL." >&2
            exit 1
        fi
    fi
    if ! "${identity[@]}" test -w "$directory" || ! "${identity[@]}" test -x "$directory"; then
        echo "$directory is not writable/searchable by $("${identity[@]}" id). Check the bind mount, host ACL and PUID/PGID." >&2
        exit 1
    fi
done

config_dir=/config/qBittorrent/config
search_dir=/config/qBittorrent/data/nova3/engines
defaults_dir=/usr/local/qbittorrent/defaults
"${identity[@]}" mkdir -p "$config_dir" "$search_dir"
if [[ ! -e "$config_dir/qBittorrent.conf" ]]; then
    "${identity[@]}" cp "$defaults_dir/qBittorrent.conf" "$config_dir/qBittorrent.conf"
fi
"${identity[@]}" cp -ru "$defaults_dir/Search/." "$search_dir/"
"${identity[@]}" python3 /usr/local/lib/qbittorrent/configure-webui.py "$config_dir/qBittorrent.conf"

unset WEBUI_PASSWORD WEBUI_PASSWORD_FILE WEB_PASSWORD WEB_PASSWORD_FILE
exec "${identity[@]}" "$@" --webui-port="$webui_port" --profile=/config
