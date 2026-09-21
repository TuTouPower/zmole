# zmole

把开源 CLI [mole](https://github.com/tw93/mole)（命令 `mo`）包装成 macOS 桌面应用。目标用户：不想记 CLI、又需要清理 / 卸载 / 优化 / 磁盘分析 / 状态监控的 Mac 用户。

从仓库模板复制而来。工具链在 `.repo_template/`，业务文件在仓根其它目录。

> 说明：上游 mole 仓库另有独立商业桌面端 [Mole for Mac](https://mole.fit/)。本仓是社区向的 CLI 包装，不绑定、不依赖该商业 App。

## 技术栈

- **UI**：SwiftUI（macOS 原生）
- **桥接**：通过 `Process` / 管道调用本机已安装的 `mo`
- **依赖**：用户需先安装 mole CLI（Homebrew：`brew install mole`，或上游 install 脚本）
- **上游源码（本机）**：已克隆至 `~/kar/github_repo/mole`，供对照 CLI 行为与接口；运行时仍调用已安装的 `mo`，不从此路径打包

## 入口

- Agent 规则：[`AGENTS.md`](AGENTS.md)
- 模板用法（消费仓 agent）：[`.repo_template/docs/usage.md`](.repo_template/docs/usage.md)
- 项目约定：[`docs/blueprint/conventions.md`](docs/blueprint/conventions.md)
- 测试方法：[`docs/blueprint/testing.md`](docs/blueprint/testing.md)
- 架构 / 领域：[`docs/blueprint/architecture.md`](docs/blueprint/architecture.md)、[`docs/blueprint/domain.md`](docs/blueprint/domain.md)

```bash
python3 .repo_template/scripts/task.py --help
python3 .repo_template/scripts/pending.py --help
python3 .repo_template/scripts/findings.py --help
python3 .repo_template/scripts/spikes.py --help
```

## 开发（待 Xcode 工程落地后）

```bash
# 打开工程（路径以实际 .xcodeproj 为准）
open Zmole.xcodeproj

# 或命令行构建
xcodebuild -scheme Zmole -configuration Debug build
```
