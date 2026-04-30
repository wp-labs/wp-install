# Changelog

## [Unreleased]

### Added

- `inst-x.sh` 支持 `monitor-docker` 目标，从 `wp-labs/wp-monitor` 下载 `start.sh`、`docker-compose-{channel}.yml` 和 `.env.example`，然后运行 `start.sh` 启动容器监控栈
- `inst-x.sh` 新增 `NEEDS_WP_INST` 判断，`monitor-docker` 和 `wplabs-lsp` 目标跳过 `wp-inst` 二进制下载
- `tests/inst-x.test.sh` — 12 个纯 shell 测试用例（零依赖），覆盖 CLI 参数解析、wp-inst 下载跳过逻辑、monitor-docker 文件下载、版本匹配跳过
- `.github/workflows/test.yml` — CI 工作流，每次 push/PR 自动运行测试

### Changed

- `inst-x.sh` channel 校验范围扩展至 `monitor-docker`
- README 新增 `monitor-docker` 使用文档和环境变量说明
