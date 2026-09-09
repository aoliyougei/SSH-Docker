# SSH Docker 容器设计

## 目标

构建一个基于 Debian 13 的容器，允许用户通过 SSH 公钥以普通用户 `aoliyougei` 登录，并执行 Bash 脚本。镜像同时提供 `curl` 和系统 CA 证书。

## 镜像与软件

- 基础镜像：`debian:13-slim`
- 安装包：`openssh-server`、`bash`、`curl`、`ca-certificates`
- SSH 登录用户：`aoliyougei`
- `aoliyougei` 不拥有 `sudo` 权限

## SSH 安全配置

- 仅允许公钥认证
- 禁用密码与交互式认证
- 禁止 root 登录
- `aoliyougei` 的公钥文件固定为 `/etc/ssh/authorized_keys/aoliyougei`
- 容器不接收、复制或持久化私钥

## 公钥注入

镜像不读取 `SSH_PUBLIC_KEY` 环境变量，也不在启动时生成 `authorized_keys`。运行者必须把公钥文件挂载至：

```text
/etc/ssh/authorized_keys/aoliyougei
```

Docker 使用只读 bind mount：

```bash
docker run -d --name ssh-box \
  -p 2222:22 \
  --mount type=bind,src="$HOME/.ssh/id_ed25519.pub",dst=/etc/ssh/authorized_keys/aoliyougei,readonly \
  ssh-box
```

Kubernetes 使用 Secret volume，把 Secret 的 `authorized_keys` 键映射为上述路径；文件模式设为只读。容器不修改挂载文件。

## 启动行为

- 构建镜像时生成 SSH host keys，避免每次启动修改容器文件系统。
- `sshd` 以前台模式运行，作为容器主进程。
- 公钥文件缺失时，`sshd` 仍可启动，但 `aoliyougei` 无法通过 SSH 登录。
- 容器开放 TCP 22 端口。

## 文件

- `Dockerfile`：安装软件、创建用户、配置 SSH、启动 `sshd`
- `sshd_config`：最小安全配置
- `k8s.yaml`：示例 Deployment、Service 和 Secret volume 挂载；不包含真实公钥

## 验证

通过 Docker API：

1. 构建镜像。
2. 生成一次性测试密钥。
3. 将测试公钥只读挂载到 `/etc/ssh/authorized_keys/aoliyougei`。
4. 启动容器并确认 `sshd` 正常运行。
5. 使用测试私钥以 `aoliyougei` 登录。
6. 远程确认 `whoami` 为 `aoliyougei`，并确认 `bash` 与 `curl` 可执行。
7. 删除任务创建的测试容器；测试私钥不写入项目。

## 非目标

- 密码登录
- root SSH 登录
- `sudo`
- 环境变量注入公钥
- 在镜像中内置公钥
- 额外进程管理器
