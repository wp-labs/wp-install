# wp-install

`wp-install` 提供一个轻量安装脚本 [`inst-x.sh`](/Users/zuowenjian/devspace/wp-labs/wp-install/inst-x.sh)，用于：

- 安装或复用本地已有的 `wp-inst`
- 安装 WarpParse / GX / GOPS 二进制
- 安装 `wpl-check`
- 安装 `wp-skills` 中的 skill
- 安装 `wplabs-lsp`
- 安装 `monitor-docker` 容器监控栈

## 快速开始

直接运行本地脚本：

```bash
./inst-x.sh
```

这会安装 `wp-inst` 到默认目录：

```text
$HOME/bin/wp-inst
```

如果本地已经有同版本、同来源仓库、同目标架构的 `wp-inst`，脚本会跳过重复下载。

## 用法

```bash
./inst-x.sh [wparse [stable|beta|alpha] | gx [stable|beta|alpha] | gops [stable|beta|alpha] | monitor-docker [stable|beta|alpha] | wpl-check | wp-skills [branch-or-tag] | wplabs-lsp]
```

支持的目标：

- 空参数：只安装 `wp-inst`
- `wparse`：安装 `wp-inst` 后，再安装 WarpParse manifest 制品
- `gx`：安装 `wp-inst` 后，再安装 GX manifest 制品
- `gops`：安装 `wp-inst` 后，再安装 GOPS manifest 制品
- `wpl-check`：安装 `wp-inst` 后，再安装 `wpl-check`
- `wp-skills`：下载 `wp-skills` 仓库归档，列出可用 skill，并按你的选择安装
- `wplabs-lsp`：安装 `wp-inst` 后，再调用本仓库的 `lsp_setup.sh` 安装 `wplabs-lsp`
- `monitor-docker`：从 `wp-labs/wp-monitor` 下载 `start.sh`、`docker-compose` 和 `.env.example`，然后运行 `start.sh` 启动容器监控栈

对 `wparse` / `gx` / `gops` / `monitor-docker`，第二个参数可选：

- `stable`
- `beta`
- `alpha`

默认值是 `stable`。

## 示例

只安装 `wp-inst`：

```bash
./inst-x.sh
```

安装 WarpParse stable：

```bash
./inst-x.sh wparse
```

安装 WarpParse beta：

```bash
./inst-x.sh wparse beta
```

安装 GX alpha：

```bash
./inst-x.sh gx alpha
```

安装 `wpl-check`：

```bash
./inst-x.sh wpl-check
```

安装 `wp-skills`（默认从 `main` 分支拉取，并交互选择 skill）：

```bash
./inst-x.sh wp-skills
```

安装指定分支或 tag 的 `wp-skills`：

```bash
./inst-x.sh wp-skills main
./inst-x.sh wp-skills v1.0.0
```

安装 `wplabs-lsp`：

```bash
./inst-x.sh wplabs-lsp
```

安装 `monitor-docker` alpha：

```bash
./inst-x.sh monitor-docker alpha
```

## `wp-skills`

`wp-skills` 目标会执行以下流程：

1. 从 `wp-labs/wp-skills` 下载指定分支或 tag 的归档，默认 `main`
2. 解压后扫描 `skills/` 目录
3. 列出可用 skill，并提示你输入编号
4. 支持一次选择多个 skill，多个编号使用空格分隔
5. 对每个选中的 skill，调用归档里的 `install-skill.sh` 安装到本地 skill 目录

典型目录和用途：

- `skills/wp-deploy`：`wparse` 用于部署和配置的 skill
- `skills/wpl-rule-check`：编写 `WPL` 和 `OML` 的 skill

示例交互：

```text
$ ./inst-x.sh wp-skills main
  1) wp-deploy - wparse 用于部署和配置的 skill
  2) wpl-rule-check - 编写 WPL 和 OML 的 skill
[wp-skills] 请输入要安装的 skill 编号，多个编号用空格分隔: 1 2
```

可用环境变量：

- `WP_SKILLS_REPO`
  默认：`wp-labs/wp-skills`
- `WP_SKILLS_REF`
  默认：`main`

## `wplabs-lsp`

`wplabs-lsp` 目标会调用同仓库下的 [`lsp_setup.sh`](/Users/zuowenjian/devspace/wp-labs/wp-install/lsp_setup.sh)。

也可以直接单独运行：

```bash
./lsp_setup.sh
```

`lsp_setup.sh` 默认安装：

- 仓库：`wp-labs/wplabs-lsp`
- 目标二进制：`wplabs-lsp`
- 安装目录：`$HOME/bin`

可用环境变量：

- `WPLABS_LSP_VERSION`
- `WPLABS_LSP_INSTALL_DIR`
- `WPLABS_LSP_MANIFEST_URL`

## `monitor-docker`

`monitor-docker` 目标会从 `wp-labs/wp-monitor` 仓库下载以下文件到 `$HOME/.wp-monitor/docker/`：

- `start.sh`
- `docker-compose-{channel}.yml`
- `.env.example`

然后执行 `start.sh`（传入 channel 参数），启动容器监控栈。

channel 到分支的映射：

- `stable` → `main` 分支
- `beta` → `beta` 分支
- `alpha` → `alpha` 分支

可用环境变量：

- `MONITOR_DOCKER_BASE_URL`
  默认：`https://raw.githubusercontent.com/wp-labs/wp-monitor`
- `MONITOR_DOCKER_DIR`
  默认：`$HOME/.wp-monitor/docker`

## 环境变量

### `wp-inst` 本体

- `WP_INST_REPO`
  默认：`wp-labs/wp-update`
- `WP_INST_VERSION`
  默认：`latest`
- `WP_INST_INSTALL_DIR`
  默认：`$HOME/bin`

### Manifest 来源

- `WP_INST_UPDATES_BASE_URL`
  默认：`https://raw.githubusercontent.com/wp-labs/wp-install/main/updates`
- `GX_UPDATES_BASE_URL`
  默认：`https://raw.githubusercontent.com/galaxy-sec/get/main/updates/gx`
- `GOPS_UPDATES_BASE_URL`
  默认：`https://raw.githubusercontent.com/galaxy-sec/get/main/updates/gops`

### Skills

- `WP_SKILLS_REPO`
  默认：`wp-labs/wp-skills`
- `WP_SKILLS_REF`
  默认：`main`

### LSP

- `WPLABS_LSP_VERSION`
  默认：`latest`
- `WPLABS_LSP_INSTALL_DIR`
  默认：`$HOME/bin`
- `WPLABS_LSP_MANIFEST_URL`
  默认：`https://raw.githubusercontent.com/wp-labs/wplabs-lsp/main/dist/install-manifest.json`

### Monitor Docker

- `MONITOR_DOCKER_BASE_URL`
  默认：`https://raw.githubusercontent.com/wp-labs/wp-monitor`
- `MONITOR_DOCKER_DIR`
  默认：`$HOME/.wp-monitor/docker`

示例：

```bash
WP_INST_VERSION=v0.1.9 ./inst-x.sh
WP_INST_INSTALL_DIR=/usr/local/bin ./inst-x.sh
WP_SKILLS_REF=v1.0.0 ./inst-x.sh wp-skills
WP_SKILLS_REPO=wp-labs/wp-skills ./inst-x.sh wp-skills
WPLABS_LSP_VERSION=0.1.1 ./inst-x.sh wplabs-lsp
MONITOR_DOCKER_DIR=/srv/monitor ./inst-x.sh monitor-docker alpha
```

## 脚本行为

脚本会先解析目标平台：

- `aarch64-apple-darwin`
- `x86_64-apple-darwin`
- `aarch64-unknown-linux-gnu`
- `x86_64-unknown-linux-gnu`

然后下载对应的 `wp-inst` release 资产：

```text
wp-inst-<tag>-<target-triple>
```

安装成功后，会在安装目录写入一个元数据文件：

```text
.wp-inst-release-meta
```

它用于判断后续运行时能否跳过重复下载。跳过条件同时要求：

- 本地 `wp-inst -V` 版本与目标版本一致
- 记录的 `repo` 与当前 `WP_INST_REPO` 一致
- 记录的 `target` 与当前平台目标一致

## PATH

安装完成后，请确保安装目录在 `PATH` 中，例如：

```bash
export PATH="$HOME/bin:$PATH"
```
