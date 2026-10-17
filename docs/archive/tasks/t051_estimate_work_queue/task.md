---
tid: "t051"
slug: "estimate_work_queue"
title: "概览估算逐项领取并发布完成分段"
status: "done"
branch: "t051_estimate_work_queue"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "fb734c72b2768a7dde1e99b5eb45a54920a30020"
depends_on: "t048"
conflicts_with: "t046,t057"
note: "用户 2026-10-17 批准；同日架构审阅授权修订：估算聚合与全局调度分离，空闲通道领取；逐段发布且保持输入版本与时间戳。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

### 需求修订（2026-10-17T23:15:20+08:00）

- 授权：用户要求按架构质量、设计完整性和技术债修复全部待办 task；本次仅修订目标文档，尚未实施。
- 决策与追溯：保留队列与渐进分段目标，区分估算聚合与全局调度；后端接口可被统一测量替换，不把固定 CLI 切片固化为架构。
- AC 变更：保留 AC-001～AC-006 的行为归属；新增 AC-007、AC-008。

### 实施进展（2026-10-18T04:14:00+08:00）

- 动态工作队列：重构 `StorageEstimateLoader`，移除原固定模数分片（`index % channels.count`），改为由各通道从 `ProbeWorkQueue` 动态竞争领取下一项。
- 初始目录排队优先：初始大目录 `/Applications`、`~/Library/Developer`、`/Users` 稳定排在系统子项前；任一通道完成大目录后立即领取系统子项，无需等待 `/Users` 结束。
- 渐进分段发布：`loadSums` 增加 `onProgress` 回调，`ProbeAggregator` 在各分段计算完成后即时触发通知；`OverviewViewModel` 在收到分段事件后立即更新对应的 `breakdown` 属性，未完成段保持占位。
- 稳健性保障：必要系统子项失败时标记系统段不可用，不展示部分和；`/System/Volumes` 保持排除；取消与旧世代事件不作为新鲜结果入库。
- 验证：编写 `EstimateWorkQueueTests.swift` 覆盖 AC-001～AC-008；全量 367 个单元测试与 4 个集成测试全部通过。

## Review 处置

### Round 1 (2026-10-18T04:15:00+08:00)

Round 1 零 finding

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：367 个单元测试全绿，4 个集成测试全绿
- 黑盒：非 UI 视觉变更，已由真实并发加载与分段事件单测覆盖
- review：full 级审查完成，零 finding
- AC 证据：见 `handoff.json`

### 结果摘要

- 实现了概览估算通道池的动态工作队列与分段渐进发布机制。
- 初始大目录按稳定顺序先入队，空闲通道可先行完成系统段而无需等待 `/Users` 返回。
- 完成分段立即可见更新，旧世代与取消事件严格隔离。
