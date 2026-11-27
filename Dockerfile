# Build context: repository root
ARG CADDY_VERSION=2.11.9

FROM caddy:${CADDY_VERSION}-builder AS builder

# The official builder sets CADDY_VERSION for xcaddy.
# DNSPod's latest release uses the old libdns API; pin its libdns 1.x port.
RUN xcaddy build \
    --with github.com/mholt/caddy-dynamicdns \
    --with github.com/caddy-dns/tencentcloud \
    --with github.com/caddy-dns/dnspod@fb7cc31cc04c68a304b8d2672c3e5d9f2ad3d7ba \
    --with github.com/caddy-dns/alidns \
    --with github.com/caddy-dns/huaweicloud \
    --with github.com/caddy-dns/cloudflare

FROM caddy:${CADDY_VERSION}

COPY --from=builder /usr/bin/caddy /usr/bin/caddy

# Fail the build if any expected module is missing.
RUN set -eu; \
    caddy version; \
    caddy list-modules > /tmp/caddy-modules; \
    grep -Fx 'dynamic_dns' /tmp/caddy-modules; \
    for provider in tencentcloud dnspod alidns huaweicloud cloudflare; do \
        grep -Fx "dns.providers.${provider}" /tmp/caddy-modules; \
    done; \
    rm /tmp/caddy-modules

# 安装 Bash
RUN apk add --no-cache bash

# Keep all user configuration and persistent state in one bind mount.
ENV XDG_DATA_HOME=/config/data \
    XDG_CONFIG_HOME=/config/runtime

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

COPY reload-caddy.sh /srv/reload-caddy.sh
RUN chmod +x /srv/reload-caddy.sh \
    && ln -s /srv/reload-caddy.sh /usr/local/bin/reload-caddy

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["caddy", "run", "--config", "/config/Caddyfile", "--adapter", "caddyfile"]
