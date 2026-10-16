# Task spec

## 背景

当前 App 装配把所有一次性 mole 命令（analyze、history、uninstall --list/dry-run/执行、clean、optimize、purge、installer list/remove、--version）共用一个 `MoleBridge`（内部单 active runner，第二个请求抛 `MoleBridgeError.busy`），只有 `status --watch` 与 `clean --dry-run` 流各占一条独立通道。后果：只读、慢扫描、写入全被串成一条线，实测 `analyze --json /` 约 2m41s，期间任何其它页面命令都被拒为 busy。mole 本身是多进程脚本，可并发运行不同子命令；串行是 App 层的设计缺陷。

来源 pending `p006`。核实（2026-10-16）：问题仍存在。

## 契约区

### 范围

- 按命令类型定义执行通道：只读命令可并发；写入命令保持单一写入通道并用 `OperationCoordinator` 租约互斥；长驻流（status watch、clean dry-run 流）各自独立通道。
- 只读命令至少包含：`status --json`、`history --json`、`analyze --json`、`uninstall --list`、`installer --list-json`。
- 各功能页装配到对应通道；同一功能页在一次请求未完成前不得重复提交（保持现有约束）。
- `MoleBridgeError.busy` 仅在写入通道或同页重复提交时出现；只读并发不得互相 busy。

### 非范围

- 不改 mole 的扫描规则或删除语义。
- 不改界面布局、文案与命令参数。
- 不实现用户可见的命令队列/进度排队界面。

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：当一个只读命令长时间未结束时，另一个只读命令仍能成功发起，不被拒绝为 busy。
- [ ] AC-002：`status --watch` 长驻期间发起的只读命令不会被拒绝为 busy。
- [ ] AC-003：两个写入命令不会同时执行；并发发起时第二个被互斥拒绝或排队，不同时 spawn。
- [ ] AC-004：同一功能页在一次请求未完成前重复提交只有一个命令在飞。

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001–AC-004：注入可控阻塞的假 process / streaming 与 coordinator spy 自动断言并发与互斥。

## 上下文区

- 来源：`p006`（用户实测反馈 2026-10-16；核实问题仍存在）
- 相关：`p007`（概览估算需独立只读通道）、`p008`（busy 语义）

### 有意不测

- 真机多进程资源占用（内存/CPU）：不进自动测试，仅记录观察。
- 具体通道数量上限：由实现决定，不作为行为 AC。

### 测试策略

- 用可阻塞的假 `MoleProcessControlling`/`MoleStreaming`，让一个命令挂起，断言另一个只读命令能发起、写入命令互斥。

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无

### 风险与回退

- 风险：拆多通道后并发进程数上升，个别命令（清除类）误并发。
- 回退：写入仍由 `OperationCoordinator` 单一租约封住；保留“单通道”配置开关以便回退。

### 依赖与约束

- 无前置 task；`p007`、`p008` 的 task 依赖本 task（复用通道模型与 busy 语义）。
- macOS 13+；`OperationCoordinator` 租约语义不变。

### Finalization 时更新的 blueprint

- `docs/blueprint/architecture.md`：命令并发通道分类（只读并发/写入串行/流独立）。
