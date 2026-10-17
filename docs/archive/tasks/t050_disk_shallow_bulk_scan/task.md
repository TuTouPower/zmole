---
tid: "t050"
slug: "disk_shallow_bulk_scan"
title: "统一测量后端的元数据预取对照试验"
status: "done"
branch: "t050_disk_shallow_bulk_scan"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "6f0f25d5623b8b1b79a1f9f7013dda1a3f75b0c2"
depends_on: "t058"
conflicts_with: ""
note: "用户 2026-10-17 批准；同日架构审阅授权修订：在最终共用后端进行代表性重复对照；语义或收益证据不足则保留逐项读取。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

### 需求修订（2026-10-17T23:15:20+08:00）

- 授权：用户要求按架构质量、设计完整性和技术债修复全部待办 task；本次仅修订目标文档，尚未实施。
- 决策与追溯：保留实验性质，改为最终共用后端的代表性重复对照；不再根据单次夹具更快就切换生产，也不保留双实现。
- AC 变更：保留 AC-001、AC-002；AC-003 的单轮耗时决策退休，新增 AC-004～AC-006。

### 对照试验实施与决策结论（2026-10-18T05:08:00+08:00）

- 构建独立实验：创建 spike `s002_metadata_prefetch_benchmark`，编写 `benchmark.swift`，在代表性数据集（1000 宽目录、15 层深目录、稀疏文件、多引用硬链接及符号链接）上实现逐项 `lstat` 与 Foundation URL 批量预取。
- 语义核查（AC-001）：两套读取产出相同总大小（14,917,632 字节）、相同可读状态与直接项计数，符号链接均不跟随。
- 性能对照（AC-004）：10 轮 AB/BA 交错测量显示：逐项读取 avg=0.0115s，Foundation URL 预取 avg=0.0505s（慢 338.1%）。因 URL 堆分配与字典属性桥接开销过大，预取存在确定性性能退化。
- 架构决策：生产保持逐项 `lstat` 读取单策略，不引入双后端切换或 URL 预取，记录 ADR 014 与 finding `d002_disk_metadata_prefetch_overhead`。
- 回归测试：编写 `DiskPrefetchBenchmarkTests.swift` 覆盖全部 AC，全量 379 个单测与集成测试回归全绿。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-10-18T05:08:00+08:00)

Round 1 零 finding

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：379 个单元测试全绿，4 个集成测试全绿，pytest contract 测试全绿。
- 黑盒：xcodebuild build passed
- review：full: review_code.md & review_test.md PASS round 1, reviewed_scope f58732871d34242d, 0 finding
- AC 证据：见 `handoff.json`

### 结果摘要

- 在代表性数据集上完成了逐项 `lstat` 读取与 Foundation URL 批量预取的严谨对照试验（spike s002）。
- 实验证实 Foundation URL 预取比逐项 `lstat` 慢 338.1%（堆对象分配与属性桥接开销显著超过系统调用节约）。
- 明确维持生产 `LiveDiskScanner` 逐项 `lstat` 读取策略，不引入预取代码与双后端兼容负担，沉淀 finding d002 与 ADR 014。
