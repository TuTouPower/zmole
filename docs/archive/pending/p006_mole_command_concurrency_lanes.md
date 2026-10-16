# p006 按命令类型区分 mole 并发通道

- 来源：用户实测反馈 2026-10-16
- 内容：当前 App 装配把所有一次性 mole 命令（analyze、history、uninstall --list/dry-run/执行、clean、optimize、purge、installer list/remove、--version）共用一个 MoleBridge（单 active runner，第二个请求抛 busy），只有 status --watch 与 clean --dry-run 流各占一条独立通道。实测 `analyze --json /` 约 2m41s，导致切到安装包页扫描时命中 busy。应区分：只读命令（status/history/analyze/uninstall --list/installer --list-json）可并发，各自独立通道或小并发池；写入命令（clean/uninstall/optimize/purge --yes/installer --remove/白名单保存）保持单一写入通道并用 OperationCoordinator 租约互斥；长驻流保持独立通道。范围：`src/zmole/App/AppDependencies.swift`、`src/zmole/MoleBridge/MoleBridge.swift`（单 runner 语义）及各 ViewModel 的命令调用。
- 处理：t025
