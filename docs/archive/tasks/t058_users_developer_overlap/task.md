---
tid: "t058"
slug: "users_developer_overlap"
title: "概览复用统一测量并消除 Developer 重遍历"
status: "done"
branch: "t058_users_developer_overlap"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "4e6a7b02451bae4fc43e02b064bc49c94c3dfccc"
depends_on: "t051"
conflicts_with: "t046,t057"
note: "用户 2026-10-17 批准；同日架构审阅授权修订：使用同一有界测量会话取得 users 总量及 Developer 归属，移除旧概览 analyze 通道与拆路径方案。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

### 需求修订（2026-10-17T23:15:20+08:00）

- 授权：用户要求按架构质量、设计完整性和技术债修复全部待办 task；本次仅修订目标文档，尚未实施。
- 决策与追溯：撤回禁止祖先路径、强制现有 CLI 的拆路径方案；概览复用有界测量会话，一次 users 遍历取得 Developer 归属，并移除旧概览探测装配。
- AC 变更：AC-001 的禁止祖先路径契约退休；保留 AC-002、AC-003 的分类/完整性意图，新增 AC-004～AC-010，覆盖最终后端的资源默认值复核。

### 统一测量后端接入与消除重遍历实施（2026-10-18T04:55:00+08:00）

- `DiskMeasurementSession` 扩展：新增 `measureSubtreeOutcome` 与 `isSubtreeReadable`，支持等待指定命名子树测量完成并安全提取统计结果。
- `StorageEstimateLoader` 重构：支持注入统一 `DiskMeasurementSession`；一轮 `/Users` 遍历同时获取包含 Developer 的用户总量及当前用户 `Library/Developer` 命名子树统计；分类规则明确由 Developer 优先归属，跨目录硬链接归属 Developer，用户数据为 users 减 Developer 贡献。保留 channel fallback 供单测兼容。
- 缓存口径升级：`StorageEstimateCache.schemaVersion` 由 2 升级至 3，旧 schema 1/2 缓存整体丢弃重算。
- `AppDependencies` 消除通道：移除 `estimatePool` 独立通道与 analyze 目录命令通道装配，直接将 `analyzeViewModel.session` 注入 `StorageEstimateLoader`。
- 测试环境保护：`ZmoleApp` 增加 `isTesting` 判定，避免测试运行期间宿主应用启动触发真实全盘 `/Users` 扫描与资源争抢。
- 验证与基准测试：编写 `OverviewUnifiedMeasureTests.swift` 覆盖 AC-002～AC-010；基准测试复核名额 1、2、3、4（Budget 1: avg=0.0241s, Budget 2: avg=0.0126s, Budget 3: avg=0.0119s, Budget 4: avg=0.0123s），确认生产默认并发名额 3 稳健适用（记录 ADR 013）。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-10-18T04:56:00+08:00)

Round 1 零 finding

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：374 个单元测试全绿，4 个集成测试全绿，pytest contract 测试全绿。
- 黑盒：xcodebuild build passed
- review：full: review_code.md & review_test.md PASS round 1, reviewed_scope 46da0104eae79a0a, 0 finding
- AC 证据：见 `handoff.json`

### 结果摘要

- 概览成功复用 `DiskMeasurementSession` 统一测量后端，一次 `/Users` 遍历同时获取包含 Developer 的用户总量及当前用户 `Library/Developer` 命名子树统计，消除独立 Developer 重遍历与旧 `estimatePool` / analyze 目录命令通道。
- 分类规则严格保证 Developer 优先归属，跨目录硬链接归属 Developer，用户数据为 users 减 Developer 贡献，非负且相加等于 users。
- 缓存版本平滑升级为 schemaVersion 3。全量 374 个单测与集成测试回归全绿。
