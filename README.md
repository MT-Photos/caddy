# Caddy 多 DNS 镜像

使用官方 `caddy` builder 镜像，通过 xcaddy 编译，再将二进制复制到官方运行镜像。
运行时只需映射 `/config` 一个目录，首次启动会自动生成默认 `Caddyfile`。

内置 DDNS（`github.com/mholt/caddy-dynamicdns`）及以下 5个常用的 DNS 插件：

- 腾讯云 `tencentcloud`、旧版 DNSPod `dnspod`、阿里云 `alidns`、华为云 `huaweicloud`  `cloudflare`

## 构建

- `build:docker`：构建当前架构镜像 `mtphotos/caddy:local`。
- `build:docker:x86` / `build:docker:arm`：通过 buildx 分别构建并加载 AMD64 / ARM64 镜像，标签为 `amd64-local` / `arm64-local`。
- `check:modules` / `check:modules:x86` / `check:modules:arm`：查看对应镜像的模块；运行异构镜像需要模拟器支持。
- `publish:docker`：构建 AMD64 和 ARM64 多架构镜像并推送到 `mtphotos/caddy:latest`，需先配置 buildx 并登录有推送权限的账号。

单架构构建可追加参数，例如 `npm run build:docker -- --build-arg CADDY_VERSION=<具体版本>`。

相关构建命令：

```sh
# 构建当前架构镜像
docker build -t mtphotos/caddy:local .

#通过 buildx 分别构建并加载 AMD64 / ARM64 镜像
docker buildx build --platform linux/amd64 --load -t mtphotos/caddy:amd64-local .
docker buildx build --platform linux/arm64 --load -t mtphotos/caddy:arm64-local .

#查看对应镜像的模块；运行异构镜像需要模拟器支持
docker run --rm mtphotos/caddy:local caddy list-modules --packages
docker run --rm --platform linux/amd64 mtphotos/caddy:amd64-local caddy list-modules --packages
docker run --rm --platform linux/arm64 mtphotos/caddy:arm64-local caddy list-modules --packages
```

构建过程中会检查 DDNS 和全部 DNS 模块是否存在。默认 `CADDY_VERSION=2`，
跟随官方 Caddy 2 镜像；xcaddy 使用官方 builder 设置的 Caddy 版本。
可通过 `--build-arg CADDY_VERSION=<具体版本>` 选择对应的官方镜像。
DNSPod 固定到 `fb7cc31cc04c68a304b8d2672c3e5d9f2ad3d7ba`，该提交已适配 libdns 1.x。
默认发布版仍依赖旧 libdns，直接使用不带版本的 `--with github.com/caddy-dns/dnspod`
会出现 `record.ID undefined`、`record.Name undefined` 等编译错误。
其余插件当前跟随各仓库默认版本，DNS API 尚未实际验证。
已通过 AMD64 镜像联合编译及 DDNS、5 个 DNS 模块存在性检查（Caddy 2.11.7）。
发布前应固定经过验证的 Caddy 版本，并在 Dockerfile 的 `--with` 模块路径后添加
`@<tag或commit>` 锁定插件版本。

多架构发布（需先配置 buildx，并将镜像名替换为有推送权限的仓库）：

```sh
docker buildx build --platform linux/amd64,linux/arm64 -t YOUR_REGISTRY/caddy:YOUR_TAG --push docker-build-v2/caddy
```

## 运行

只需将宿主机的一个文件夹映射到 `/config`，无需提前创建 `Caddyfile`。
必须直接挂载 `/config`；未挂载时容器会报错退出，不会创建配置或数据目录。
每次启动时，若 `/config/Caddyfile.txt` 存在，则将其复制并覆盖 `/config/Caddyfile`。
若没有 `Caddyfile.txt`，则保留已有 `Caddyfile`，或在文件不存在时生成默认配置。
若 `Caddyfile` 是目录，启动会报错，需先将其改名或移走。

| 容器路径 | 用途 |
| --- | --- |
| `/config/Caddyfile` | 用户编辑的配置文件 |
| `/config/Caddyfile.txt` | 可选的启动配置源，每次启动时覆盖 `Caddyfile` |
| `/config/data/caddy/` | 证书、私钥、ACME 账户等持久化数据 |
| `/config/runtime/caddy/` | 自动保存的 JSON 配置 |

以下示例使用前面构建的 AMD64 本地镜像；ARM64 请将镜像标签改为 `arm64-local`。

### docker run

在 Bash 中运行：

```sh
mkdir -p config
docker run -d \
  --name mtphotos-caddy \
  --restart unless-stopped \
  -p 8280:80 \
  -p 8443:443 \
  -p 8443:443/udp \
  --mount "type=bind,source=$(pwd)/config,target=/config" \
  mtphotos/caddy:amd64-local
```

PowerShell 示例：

```powershell
New-Item -ItemType Directory -Force -Path ./config | Out-Null
docker run -d --name mtphotos-caddy --restart unless-stopped -p 8280:80 -p 8443:443 -p 8443:443/udp --mount "type=bind,source=$($PWD.Path)/config,target=/config" mtphotos/caddy:amd64-local
```

Unraid 将路径映射设置为 `/mnt/user/appdata/caddy` → `/config`（读写），
替换上述命令的目录映射即可，例如：

```sh
-v /mnt/user/appdata/caddy:/config:rw
```

### Docker Compose

将以下内容保存为 `compose.yaml`，数据会保存在同目录的 `config` 文件夹中：

```yaml
services:
  caddy:
    image: mtphotos/caddy:amd64-local
    container_name: mtphotos-caddy
    restart: unless-stopped
    ports:
      - "8280:80"
      - "8443:443"
      - "8443:443/udp"
    volumes:
      - ./config:/config
```

在该目录启动：

```sh
docker compose up -d
docker compose logs -f caddy
```

上述两种方式任选一种。首次启动后通过 `http://宿主机IP:8280` 查看默认测试页面。
编辑宿主机的 `config/Caddyfile` 后，可执行以下命令加载配置：

```sh
docker exec mtphotos-caddy caddy reload --config /config/Caddyfile --adapter caddyfile
```

配置 HTTPS 站点后，通过 `https://你的域名:8443` 访问；如需使用标准端口，
将 `8280:80` 改为 `80:80`，TCP 和 UDP 的 `8443:443` 均改为 `443:443`。
使用 DNS 插件时，请按 `Caddyfile` 中引用的环境变量，为容器配置对应的 DNS API 凭据。

### 从旧的目录映射迁移

先停止旧容器并备份原目录，再将原 `Caddyfile` 放到新宿主机目录的 `Caddyfile`，
原 `/data` 的内容放到新目录的 `data/`，原 `/config` 的内容放到新目录的 `runtime/`。
例如原 `/data/caddy` 应对应新目录的 `data/caddy`，避免丢失已有证书和 ACME 账户。
最后将容器映射改为新目录 → `/config`，使用新镜像启动。
