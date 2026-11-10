#!/bin/sh
set -eu

# Caddyfile 在容器内的路径
CONFIG="/etc/caddy/Caddyfile"

echo "正在检查配置..."
caddy validate --config "$CONFIG" --adapter caddyfile

echo "正在应用配置..."
caddy reload --config "$CONFIG" --adapter caddyfile

echo "配置更新成功"
