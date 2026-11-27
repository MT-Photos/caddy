# Caddy 多 DNS 镜像

使用官方 `caddy` builder 镜像，通过 xcaddy 编译，再将二进制复制到官方运行镜像。
运行时只需映射 `/config` 一个目录，首次启动会自动生成默认 `Caddyfile`。

内置 DDNS（`github.com/mholt/caddy-dynamicdns`） 及以下 5个常用的 DNS 插件：

- 腾讯云 `tencentcloud`
- 旧版 DNSPod `dnspod`
- 阿里云 `alidns`
- 华为云 `huaweicloud` 
- `cloudflare`

## 构建

相关构建命令：

```sh
# 构建当前架构镜像
docker build -t mtphotos/caddy:latest .

#通过 buildx 分别构建并加载 AMD64 / ARM64 镜像
docker buildx build --platform linux/amd64 --load -t mtphotos/caddy:x86 .
docker buildx build --platform linux/arm64 --load -t mtphotos/caddy:arm .

#查看对应镜像的模块；运行异构镜像需要模拟器支持
docker run --rm mtphotos/caddy:latest caddy list-modules --packages
docker run --rm --platform linux/amd64 mtphotos/caddy:x86 caddy list-modules --packages
docker run --rm --platform linux/arm64 mtphotos/caddy:arm caddy list-modules --packages
```

构建过程中会检查 DDNS 和全部 DNS 模块是否存在。默认 `CADDY_VERSION=2.11.9`，
跟随官方 Caddy 2 镜像；xcaddy 使用官方 builder 设置的 Caddy 版本。

可通过 `--build-arg CADDY_VERSION=<具体版本>` 选择对应的官方镜像。

DNSPod 固定到 `fb7cc31cc04c68a304b8d2672c3e5d9f2ad3d7ba`，该提交已适配 libdns 1.x。

默认发布版仍依赖旧 libdns，直接使用不带版本的 `--with github.com/caddy-dns/dnspod`
会出现 `record.ID undefined`、`record.Name undefined` 等编译错误。

其余插件当前跟随各仓库默认版本，DNS API 尚未实际验证。

已通过 AMD64 镜像联合编译及 DDNS、5 个 DNS 模块存在性检查（Caddy 2.11.9）。

发布前应固定经过验证的 Caddy 版本，并在 Dockerfile 的 `--with` 模块路径后添加 `@<tag或commit>` 锁定插件版本。

## GitHub Actions 构建与推送

项目已配置两步式手动发布工作流，支持**单次编译**同时构建 `linux/amd64` 与 `linux/arm64` 多架构镜像并推送至 **Docker Hub**（`mtphotos/caddy`）与 **阿里云镜像仓库**（`registry.cn-hangzhou.aliyuncs.com/mtphotos/caddy`）（推送代码到 `master` 分支不会触发自动构建）：

1. **构建并推送版本镜像**（[`.github/workflows/docker-publish.yml`](.github/workflows/docker-publish.yml)）
   - **触发时机**：在 GitHub 仓库 **Actions -> Build and Push Docker Image -> Run workflow** 手动触发（可选填 `caddy_version` 指定或覆盖版本，并通过 `push_dockerhub`、`push_aliyun` 勾选目标仓库；全部取消勾选则仅做构建测试）。
   - **发布标签**：自动读取 `Dockerfile` 中的 `CADDY_VERSION`，推送多架构标签 `<仓库>:<CADDY_VERSION>`（**默认不推送 `latest`**）。
2. **手动升级 `latest` 标签**（[`.github/workflows/promote-latest.yml`](.github/workflows/promote-latest.yml)）
   - 验证版本镜像无误后，在 GitHub 仓库 **Actions -> Promote to Latest -> Run workflow** 手动点击触发（`version` 留空默认读取 `Dockerfile` 中的 `CADDY_VERSION`，可通过 `promote_dockerhub`、`promote_aliyun` 勾选目标仓库）。
   - 通过 `docker buildx imagetools create` 直接将已发布的多架构版本清单指向 `<仓库>:latest`，无需重新编译，确保 `latest` 与已验证版本完全一致。

- **前置配置**：在 GitHub 仓库 `Settings -> Secrets and variables -> Actions` 中配置：
  - **Secrets**：
    - `DOCKERHUB_USERNAME`：Docker Hub 用户名
    - `DOCKERHUB_TOKEN`：Docker Hub Access Token（需具备 Read & Write 权限）
    - `ALIYUN_REGISTRY_USERNAME`：阿里云容器镜像服务登录用户名
    - `ALIYUN_REGISTRY_PASSWORD`：阿里云容器镜像服务登录密码（固定密码或访问凭证）
  - **Variables（可选）**：
    - `DOCKERHUB_REPO`：自定义 Docker Hub 推送目标仓库名（默认 `mtphotos/caddy`）
    - `ALIYUN_REGISTRY_REPO`：自定义阿里云推送目标仓库地址（默认 `registry.cn-hangzhou.aliyuncs.com/mtphotos/caddy`）

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

Docker Hub 发布的镜像已同时支持 AMD64 和 ARM64；如使用前面本地单独构建的镜像，请将标签改为对应架构（如 `x86` 或 `arm`）。

### docker run

在 Bash 中运行：

```sh
mkdir -p config
docker run -d \
  --name caddy \
  --restart unless-stopped \
  -p 8280:80 \
  -p 8443:443 \
  -p 8443:443/udp \
  -v /xxx/caddy:/config \
  mtphotos/caddy:latest
```

PowerShell 示例：

```powershell
New-Item -ItemType Directory -Force -Path ./config | Out-Null
docker run -d --name mtphotos-caddy --restart unless-stopped -p 8280:80 -p 8443:443 -p 8443:443/udp -v /xxx/caddy:/config mtphotos/caddy:latest
```

### Docker Compose

将以下内容保存为 `compose.yaml`，数据会保存在同目录的 `config` 文件夹中：

```yaml
services:
  caddy:
    image: mtphotos/caddy:latest
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

### 访问

上述两种方式任选一种。首次启动后通过 `http://宿主机IP:8280` 查看默认测试页面。

编辑宿主机的 `config/Caddyfile` 后，可执行以下命令加载配置：

```sh
docker exec caddy reload-caddy
# 也就是 打开caddy容器的终端，输入 reload-caddy 回车 
```
#### HTTPS

配置 HTTPS 站点后，通过 `https://你的域名:8443` 访问；如需使用标准端口，

将 `8280:80` 改为 `80:80`，TCP 和 UDP 的 `8443:443` 均改为 `443:443`。

使用 DNS 插件时，请按 `Caddyfile` 中引用的环境变量，为容器配置对应的 DNS API 凭据。


### Caddyfile 示例

```text
# 这是使用腾讯云 `tencentcloud` 申请 ssl证书的配置示例
# {} 是读取 容器环境变量 ，也可以在这边添加对应的邮箱地址、secret_id、secret_key
{
    email {$dns_dnspod_email}

    acme_dns tencentcloud {
        secret_id {env.TENCENTCLOUD_SECRET_ID}
        secret_key {env.TENCENTCLOUD_SECRET_KEY}
    }

    auto_https disable_redirects
}

# 这是访问端口的默认返回内容
:80 {
	respond "Caddy is running"
}

(proxy_defaults) {
	header_up X-Real-IP {remote_host}
}

# 申请泛域名证书 ， example.com 替换为 你的域名
https://*.example.com {
	abort
}


http://mt.example.com, https://mt.example.com {

	# 这些 IP 免认证；其他 IP 需要认证
	@needAuth not remote_ip 192.168.31.0/24
	
    # 这是 basic_auth 的示例,  mt 是账号，  $2a$1... 是密码，密码生成方法见教程下一部分；
	basic_auth  @needAuth {
		mt $2a$14$RwtiG/6RO2dE2wqaHzKwe2XsvFCIIvRk6Meq0dvMTQfV8OuEmazSG
	}
	log {
		level ERROR
	}

    # 192.168.31.191:8063 是MT Photos在局域网访问的地址
	reverse_proxy 192.168.31.191:8063 {
		import proxy_defaults
	}
}

```


### 生成BasicAuth密码

Caddy 的 Basic Auth（HTTP 基础认证）需要配置 用户名和密码哈希值，不能直接填写明文密码。

在 Caddy 2.11.x 中，使用 `basic_auth` 指令。

#### 1. Caddyfile 配置示例

```
https://mt.example.com {
    basic_auth {
        admin $2a$14$xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    }

    reverse_proxy 192.168.1.100:8063
}
```

其中：

- `admin`：用户名，可以自行修改。
- `$2a$14$...`：密码的 bcrypt 哈希值，需要使用命令生成。
- `basic_auth`：默认保护整个站点，包括反向代理的所有接口。

访问网站时，浏览器会弹出用户名和密码输入框。

#### 2. 生成密码哈希值

如果使用 Docker 部署 Caddy，推荐直接执行：

```
docker exec -it caddy caddy hash-password
```

执行后会交互式要求输入密码，然后输出 bcrypt 哈希值。

假设生成的结果是：

```
$2a$14$xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

把它复制到 Caddyfile 中即可。

不需要对密码进行 Base64 编码，也不需要手动添加引号。

#### 3. 配置多个账号

可以直接增加多行：

```
basic_auth {
    admin $2a$14$HASH_FOR_ADMIN
    user1 $2a$14$HASH_FOR_USER1
    user2 $2a$14$HASH_FOR_USER2
}
```

每个用户的密码分别生成。

#### 4. 修改配置后生效

重启caddy容器， 或者输入下面的命令重新加载配置

```
docker exec caddy reload-caddy
```

#### 5. 注意事项

- 必须使用 HTTPS：Basic Auth 并不是加密传输密码，HTTP 下很容易泄露凭据。
- 密码哈希不等于加密：bcrypt 是单向哈希，无法从哈希值直接还原密码。
- NAS App 兼容性：如果反向代理的是 MT Photos，Basic Auth 可能影响移动 App 的 API、图片和视频访问，因为客户端不一定自动处理 HTTP 401 认证。

官方参考：[Caddy basic_auth 文档](https://caddyserver.com/docs/caddyfile/directives/basic_auth)。

### 从旧的目录映射迁移

先停止旧容器并备份原目录，再将原 `Caddyfile` 放到新宿主机目录的 `Caddyfile.txt`，
原 `/data` 的内容放到新目录的 `data/`，原 `/config` 的内容放到新目录的 `runtime/`。
例如原 `/data/caddy` 应对应新目录的 `data/caddy`，避免丢失已有证书和 ACME 账户。
最后将容器映射改为新目录 → `/config`，使用新镜像启动。
