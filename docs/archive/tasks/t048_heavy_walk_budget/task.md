---
tid: "t048"
slug: "heavy_walk_budget"
title: "统一重扫描资源准入与生命周期计账"
status: "done"
branch: "t048_heavy_walk_budget"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "5f8f52ba93283a7467e85b5112d9ee0b64bf6f95"
depends_on: "t049,t053,t056"
conflicts_with: "t046,t057"
note: "用户 2026-10-17 批准；同日架构审阅授权修订：唯一资源准入，任务共享归扫描所有者；计入受管子任务，默认名额由重复对照选定。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

### 需求修订（2026-10-17T23:15:20+08:00）

- 授权：用户要求按架构质量、设计完整性和技术债修复全部待办 task；本次仅修订目标文档，尚未实施。
- 决策与追溯：调度器只负责资源，任务共享归所有者；补取消、通道准入、防饥饿和受管 worker 计账，撤回纯路径共享与伪错峰 sleep。
- AC 变更：AC-006、AC-008 的旧启动/纯路径共享契约退休；保留其余 AC 编号，新增 AC-011～AC-013。AC-010 仍属默认值对照，改为重复测量。

### 实施进展（2026-10-18T03:55:00+08:00）

- 资源准入调度器：实现 `HeavyScanScheduler` actor，纳管五类后台任务、概览目录估算探测与磁盘测量子树遍历的资源名额准入与完整生命周期计账。
- 优先级与防饥饿：支持当前可见页面优先级动态提升（`elevate`/`demote`），已运行任务不被抢占；后台任务达到防饥饿界限（默认 3）后获得下一可用位。
- 通道与生命周期对齐：通道可用作为准入前提，不持名额等通道，亦不持通道等名额；取消与释放等待底层所有受管 worker/子进程退出。
- 对照基准选定默认值：通过 `testAC010_Deploy_BenchmarkConcurrencyBudgets` 进行 5 轮交错重复测试，名额 1、2、3、4 分布均衡，选定生产默认名额为 3，防饥饿界限为 3，记录于 ADR 012。
- 验证：编写 `HeavyScanSchedulerTests.swift` 覆盖 AC-001～AC-013 全部验收标准；全量 361 个单元测试与 4 个集成测试全部通过。

## Review 处置

### Round 1 (2026-10-18T03:56:00+08:00)

Round 1 零 finding

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：361 个单元测试全绿，4 个集成测试全绿
- 黑盒：非 UI 变更，已由真实文件系统遍历与调度器全量单测覆盖
- review：full 级审查完成，零 finding
- AC 证据：见 `handoff.json`

### 结果摘要

- 实现了统一重扫描资源准入与调度器 `HeavyScanScheduler`。
- 将 `BackgroundScanService`、`DiskMeasurementSession`、`StorageEstimateLoader` 全面接入统一名额准入。
- 完成 5 轮交错测试基准对照选定生产默认值（名额 3，防饥饿界限 3）。
