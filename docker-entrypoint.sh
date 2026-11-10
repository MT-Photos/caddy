#!/bin/sh
set -eu

# Require an exact mount at /config before writing any persistent state.
if ! awk '$5 == "/config" { found = 1 } END { exit !found }' /proc/self/mountinfo; then
    echo >&2 "Error: /config must be mounted to a persistent host directory (for example: -v /path/to/caddy:/config)."
    exit 1
fi

mkdir -p /config/data /config/runtime

if [ -d /config/Caddyfile ]; then
    echo >&2 "Error: /config/Caddyfile is a directory; rename or move it before starting Caddy."
    exit 1
fi

if [ -f /config/Caddyfile.txt ]; then
    cp /config/Caddyfile.txt /config/Caddyfile
elif [ ! -e /config/Caddyfile ]; then
    cat > /config/Caddyfile <<'EOF'
:80 {
    respond "Caddy is running"
}
EOF
fi

exec "$@"
