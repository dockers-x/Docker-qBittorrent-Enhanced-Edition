# qBittorrent Enhanced Edition Docker

基于官方 Alpine 和上游静态二进制，支持 `amd64`、`arm64`、`arm/v7`。镜像为 `czyt/qbittorrentee`。

保留默认登录信息 **`admin / adminadmin`**，建议部署时设置自己的凭据，不要直接暴露到公网。

## 快速启动

```bash
mkdir -p ./qbittorrentee/config ./qbittorrentee/downloads
sudo chown -R "$(id -u):$(id -g)" ./qbittorrentee
```

编辑 `docker-compose.yml`，把 `PUID`、`PGID` 改为上述用户的 UID/GID，然后运行 `docker compose up -d`，访问 `http://宿主机IP:8080`。

Compose 使用长格式 bind mount 和 `create_host_path: false`，路径不存在会直接报错，不会让 Docker 自动在错误位置创建目录。

## 环境变量

以下变量均由当前 Dockerfile 或启动脚本实际实现：

| 变量 | 默认值 | 行为 |
| --- | --- | --- |
| `PUID` | `1000` | 默认模式下运行 qBittorrent 的数字 UID |
| `PGID` | `1000` | 默认模式下运行 qBittorrent 的数字 GID |
| `RUN_AS_ROOT` | `false` | 为 `true` 时不降权，以 root 运行，忽略 PUID/PGID；容器必须以 root 启动 |
| `UMASK_SET` | `022` | 新建文件权限掩码，三位或四位八进制 |
| `WEBUIPORT` | `8080` | WebUI 监听端口，范围 1–65535；端口映射须同步调整 |
| `TZ` | `Asia/Shanghai` | 时区 |
| `ENABLE_CONFIG_PERM_FIX` | `true` | root 启动时递归调整 `/config` 的 owner 为实际运行 UID/GID |
| `ENABLE_DOWNLOADS_PERM_FIX` | `false` | root 启动时递归调整 `/downloads` 的 owner；托管文稿目录应关闭 |
| `WEBUI_USERNAME` | 不设置 | 覆盖 WebUI 登录用户名 |
| `WEBUI_PASSWORD` | 不设置 | 覆盖 WebUI 密码，生成 PBKDF2-SHA512 哈希，不将明文写入配置 |
| `WEBUI_PASSWORD_FILE` | 不设置 | 从容器内 UTF-8 文件读取密码，去除结尾换行 |

兼容旧名称 `WEB_PASSWORD`、`WEB_PASSWORD_FILE`，分别等价于密码及密码文件。四种密码来源只允许设置一种，冲突或空密码会中止启动。不再声明旧文档中没有实现的其他密码变量。

不设置凭据变量时保留已有配置；只有全新配置使用 `admin / adminadmin`。用户名与密码可以分别覆盖。只要保留相应环境变量，每次启动都会重新应用，因此应通过部署配置改密，而不是只在 WebUI 中改密。

### 自定义登录信息

在 Compose 的 `environment` 中添加：

```yaml
      - WEBUI_USERNAME=myadmin
      - WEBUI_PASSWORD=replace-with-a-strong-password
```

也可挂载密码文件并设置 `WEBUI_PASSWORD_FILE=/run/secrets/qbittorrent_password`，不要同时设置明文密码变量。密码不会输出到启动日志，但环境变量和配置仍需按敏感信息管理。

### root 兼容模式

默认由 root 初始化目录，再通过 `su-exec` 切换到 PUID/PGID；不再依赖基础镜像中的 `abc` 用户或 s6 隐式初始化。`tini` 负责信号转发和子进程回收。

外层只写 `user: root` **不会**关闭默认降权，需要显式配置：

```yaml
    environment:
      - RUN_AS_ROOT=true
      - ENABLE_CONFIG_PERM_FIX=false
      - ENABLE_DOWNLOADS_PERM_FIX=false
```

镜像默认以 root 启动，无需额外设置 `user: root`。外层指定非 root 用户时直接以该 UID/GID 运行，不切换身份或执行 chown；此时不能同时设置 `RUN_AS_ROOT=true`。

root 模式拥有更大的文件访问范围，但不能绕过宿主机 ACL。不要为解决普通目录权限问题启用 `privileged` 或 `chmod 777`。

## 懒猫多实例挂载

`error while creating mount source path ... document/下载 ... operation not permitted` 表示 Docker 创建宿主机 bind mount 源目录失败，发生在容器启动之前。镜像内的 root、PUID/PGID、chown 都尚未执行，无法修复这个阶段的错误。

- `/config` 绑定应用数据 `/lzcapp/var/config`。
- 多实例文稿绑定 `/lzcapp/documents/{{ .S.DeployUID }}/下载目录:/downloads`，不能直接在文稿根目录创建“下载”目录。
- 声明 `document.private` 权限，不硬编码 `/lzc...` 系统内部路径。
- 使用 root 兼容模式时关闭两项权限修复，不递归 chown 托管文稿目录。
- 旧数据不会自动迁移，修改挂载前备份并确认文件所属用户。

这些设置属于懒猫应用项目，不是 Dockerfile。本仓库不包含 LPK 打包、免密登录或文件选择器拦截。

## 自动发布

只保留 `.github/workflows/release.yml`，替代原五个定时/手动任务：

1. 每天 **21:00 UTC（北京时间次日 05:00）**检查上游最新正式 GitHub Release，不使用未发布的 Git tag。
2. 更新并提交 `ReleaseTag`，在同一工作流直接构建，不依赖机器人提交再次触发 Actions。
3. 推送三架构镜像：版本标签、`<版本>-r1`、`latest`、`sha-<完整提交SHA>`。
4. 推送后用真实 amd64 容器检查默认登录、自定义登录及 root 模式 UID。此项为非阻塞冒烟测试，失败保留日志、警告和运行摘要，不影响本仓库 Git tag / Release 发布。构建或推送失败仍阻塞发布；Release 包含上游说明，不重复上传上游安装包。
5. 定时执行发现版本已有正式 Release 时跳过；失败时没有成功标记，下次重试。手动运行始终构建，可关闭 `check_upstream` 重建当前 `ReleaseTag`。

`-r1` 专门标识本次重写后的镜像，供懒猫跟踪，避免误用已有同版本旧镜像。未来同版本重建可能覆盖版本标签，需要严格固定时使用 digest 或 SHA 标签。

推送 `master` 的镜像相关代码也会构建；更改默认分支时须同步调整 `push.branches`。仓库须允许 Actions 写入内容，并配置 **`DOCKERHUB_TOKEN`** Secret（对 `czyt/qbittorrentee` 有推送权限）。用户名固定 `czyt`，不需要 `DOCKERHUB_USERNAME`。

## 本地构建

运行 `./build.sh`，读取 `ReleaseTag`，构建当前架构镜像并设置版本、`-r1`、`latest` 标签。额外 Docker build 参数可传给脚本，不再硬编码代理。下载失败立即退出，不把 HTTP 错误页打包成二进制。

目录：`/config` 保存配置、任务状态和搜索插件，`/downloads` 保存下载文件。端口：WebUI `8080/TCP`，BT `6881/TCP+UDP`。

## 致谢

感谢 qBittorrent、qBittorrent Enhanced Edition 及 SuperNG6 原镜像项目。本仓库保留原项目配置和搜索插件基础。
