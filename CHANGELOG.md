# Changelog

## [Unreleased]

### Added

- `inst-x.sh` 支持 `monitor-docker` 目标，从 `wp-labs/wp-monitor` 下载 `start.sh`、`docker-compose-{channel}.yml` 和 `.env.example`，然后运行 `start.sh` 启动容器监控栈
- `inst-x.sh` 新增 `NEEDS_WP_INST` 判断，`monitor-docker` 和 `wplabs-lsp` 目标跳过 `wp-inst` 二进制下载

### Changed

- `inst-x.sh` channel 校验范围扩展至 `monitor-docker`
- README 新增 `monitor-docker` 使用文档和环境变量说明
