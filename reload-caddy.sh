#!/bin/sh
set -eu

SOURCE="/config/Caddyfile.txt"
CONFIG="/config/Caddyfile"

if [ ! -f "$SOURCE" ]; then
    echo "找不到配置文件：$SOURCE" >&2
    exit 1
fi

echo "正在检查新配置..."
caddy validate --config "$SOURCE" --adapter caddyfile

echo "检查通过，正在替换正式配置..."
cp "$SOURCE" "$CONFIG"

echo "正在重载 Caddy..."
caddy reload --config "$CONFIG" --adapter caddyfile

echo "配置更新成功"