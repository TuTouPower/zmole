# Task spec

## 背景

`src/zmole/App/AppDependencies.swift` 727 行中约 500 行是 demo 假件与 fixture（`DemoMoleProcess`、`DemoMoleStreaming`、`DemoUninstallListStream`、`DemoDiskScanner`、`DemoConfiguration`、`DemoFixtures` 及分析/历史/安装包/卸载样本）。真实装配 `AppDependencies.init` 与这些假件同文件，假件随生产装配改动被动变更，review（`docs/reviews/review_20261017_054534` 的 A57，v5_architecture）判定拆分。

## 契约区

### 范围

- 把 demo 假件与所有 demo fixture 移入独立文件（建议 `src/zmole/App/DemoSupport.swift`；如有必要可再分 `DemoFixtures.swift`），`AppDependencies.swift` 只保留真实装配（`AppDependencies` 本体与 `MoleProcessBox` 等装配辅助，若其不属于 demo）。
- 行为零变化：`--demo` 系列参数（`--demo`、`--demo-page`、`--demo-state`、`--demo-language`、`--demo-appearance`、`--demo-data-root`）的语义与 demo 装配结果逐项保持现状（含 A45/A46 的门禁与临时目录限定）。
- demo 相关类型保持原可见性语义（文件内私有/模块内可见关系不被破坏）；如有 `private` 跨文件移动需求，改为文件级 `fileprivate`→模块内可见的等价调整并说明。
- 同步 `Zmole.xcodeproj`（xcodegen generate 后提交工程文件变化）。

### 非范围

- 不改变任何 demo 行为、参数语义、fixture 内容（除行布局迁移外零 diff）。
- 不重命名对外可见类型与测试引用的类型名；不顺带重构生产装配逻辑。
- 不做 A56 之外的进一步去重（fixture 去重已在 A56 落地；本 task 只做文件搬迁与组织）。

### 验收标准

<!-- 规范（门禁必留，不得删除） -->

只写可观察、可独立验证的行为；每条使用稳定且不复用的 `AC-NNN`。需真实部署或人工环境验证时在编号前加 `[deploy]`。技术选型不作为行为 AC。

<!-- /规范 -->

- [ ] AC-001：`src/zmole/App/AppDependencies.swift` 不再包含任何 `Demo*` 类型、demo fixture 字面量与 demo 专用扩展；demo 内容全部位于独立文件。
- [ ] AC-002：`xcodegen generate` 后 `xcodebuild build -scheme Zmole` 退出码 0。
- [ ] AC-003：全量 `xcodebuild test`（含全部 demo 用例：`ZmoleTests` 的 demo 配置/卸载预览/状态流、`PrewarmTests.testDemoConfigurationDisablesPrewarm`、`CommandConcurrencyTests` 的 demo 装配路径）通过。
- [ ] AC-004：三个集成脚本（clean_trash / installer_interface / uninstall_stream）通过。
- [ ] AC-005：工作副本中 `AppDependencies.swift` 行数少于拆分前的一半，且其内容只含装配与装配辅助。

### 可测试性声明

<!-- 规范（门禁必留，不得删除） -->

逐条说明不可自动测试的 AC 及替代验证；全部可测则写“全部 AC 可自动测试”。

<!-- /规范 -->

- AC-001、AC-005：源码结构断言（grep 无 `Demo` 类型定义/字符串检查）可自动。
- AC-002–AC-004：全部可自动测试。

## 上下文区

- 来源：review_20261017_054534 A57（核实日期 2026-10-17；决策见 `docs/reviews/review_20261017_054534/adoption_decision.md`）

### 有意不测

- demo UI 逐页视觉（由 `docs/guides/visual_acceptance/` 截图流程覆盖，属 A83 范围）。

### 测试策略

- 迁移后跑全量单测与集成脚本；demo 用例不改断言（行为零变化是硬约束）。
- 新增一条源码结构测试：`AppDependencies.swift` 不含 `private final class Demo`/`struct Demo`/`enum DemoFixtures` 定义。

### 未知契约清单

<!-- 规范（门禁必留，不得删除） -->

未核实的外部契约标为 `UNVERIFIED-BLOCKING` 或 `UNVERIFIED-SPIKE`；核实后改写为结论和验证方式。无则写“无”。

<!-- /规范 -->

- 无

### 风险与回退

- 风险：大块搬迁导致可见性编译错误或漏移片段。
- 回退：单 commit 纯搬迁，编译失败时按编译器错误逐项修复；回退即 revert 该 commit（无数据面影响）。

### 依赖与约束

- 前置：无（基于当前 main `dd76bb0`）。
- 约束：demo 行为零变化；不得引入 UI/行为重构。

### Finalization 时更新的 blueprint

- `docs/blueprint/architecture.md`：如 Demo 装配边界一节需按新文件结构微调引用。
