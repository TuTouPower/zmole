# Task spec

## 背景

`CleanViewModel`（Features/Clean）、`UninstallViewModel`（Features/Uninstall）、`MaintenanceViewModel`（Features/Operations）各自维护一份逐字重复的「写租约 + 预览世代」样板：`isCurrentPreview`、`releaseLease(clearPreviewGeneration:)`、`operationID(for:)`、以及 `coordinator.$invalidationGeneration` 的过期订阅（`expirePreview` + generation 清零）。同类缺陷（busy 分支缺会话终止，A43）此前三处同缺，说明重复已是缺陷复发源。review（`docs/reviews/review_20261017_054534` 的 A85，v5_architecture）建议收敛为共享 `PreviewLeaseCoordinator`/基类。

## 契约区

### 范围

- 抽出共享组件（建议 `Features/Operations/PreviewLeaseCoordinator`，形态可为组合对象或基类）统一承载：
    - 写租约的获取/释放与 `previewCoordinatorGeneration` 的接管/清除；
    - `isCurrentPreview` 判定与「协调器失效信号 → 过期预览」订阅处理；
    - 操作 ID 提取（`ready/confirming/executing` 三态）。
- `CleanViewModel`、`UninstallViewModel`、`MaintenanceViewModel` 迁移到共享实现，删除三份私有重复。
- 行为零变化：预览生命周期（预览成功 → 确认 → 执行）、确认前同代校验、租约互斥、忙碌可恢复提示、失效信号使预览过期、busy 分支的会话终止（A43 语义）逐项保持现状。

### 非范围

- 不修改 `OperationCoordinator` 与 `OperationSession` 的对外语义与状态机。
- 不改任何 UI、文案与 i18n key。
- 不合并三个 ViewModel 的其他共性（如 confirm 流程），仅收敛租约/世代样板。

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：三个 ViewModel 不再各自定义租约/世代私有成员与重复的 `isCurrentPreview`/`releaseLease`/`operationID(for:)` 实现；逻辑由共享组件提供（源码结构断言）。
- [ ] AC-002：`CommandConcurrencyTests`、`RecoverableBusyTests`、`CleanPageTests`、`CleanPreviewStoreTests`、`UninstallTests`、`UninstallDetailTests`、`BatchUninstallTests`、`OptimizeTests`、`PurgeTests`、`OptimizePurgePageTests` 全部通过（行为无回归）。
- [ ] AC-003：协调器失效信号（写入成功/外部 invalidate）仍使三个页面的已就绪预览按原语义过期并需重新预览（既有用例覆盖）。
- [ ] AC-004：全量 `xcodebuild test` 与三个集成脚本通过。

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001：源码结构断言可自动（grep 私有重复定义消失、共享类型存在）。
- AC-002–AC-004：全部可自动测试。

## 上下文区

- 来源：review_20261017_054534 A85（核实日期 2026-10-17；决策见 `docs/reviews/review_20261017_054534/adoption_decision.md`）

### 有意不测

- A43 的三处 busy 分支终止语义：沿用既有 busy 用例（可达性低），不新增注入专线残 runner 的用例。

### 测试策略

- 先以现有测试全绿作为迁移基线；迁移后全量回归（既有用例不改断言，行为零变化是硬约束）。
- 新增一条源码结构测试：三文件不含重复样板（如 `private func releaseLease(clearPreviewGeneration`）。

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无

### 风险与回退

- 风险：迁移改动触及三个核心写路径 VM，回归面较大；共享组件接口设计不足会引入微妙行为差异。
- 回退：单 commit 完成迁移，任何回归以 revert 该 commit 恢复；不建议半迁移状态（易出现双轨逻辑）。

### 依赖与约束

- 前置：无（基于当前 main `dd76bb0`）。
- 约束：行为零变化；不得顺带修改 Session/Coordinator 语义；与 t040（概览估算）改动面不重叠（若并行实施，注意 `AppDependencies` 装配段的行级冲突）。
- 建议：实施前先跑一次全量 `xcodebuild test` 记录基线（当前全部通过）。

### Finalization 时更新的 blueprint

- `docs/blueprint/architecture.md`：`App 装配与共享协调` 一节补充共享预览租约组件职责。
