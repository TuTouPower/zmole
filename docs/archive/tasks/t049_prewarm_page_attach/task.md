---
tid: "t049"
slug: "prewarm_page_attach"
title: "统一名单扫描所有权与页面订阅"
status: "done"
branch: "t049_prewarm_page_attach"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "1fdc10306d2325f9a30fdf951fb78f9520758ec6"
depends_on: "t047"
conflicts_with: "t045,t046,t055"
note: "用户 2026-10-17 批准；同日架构审阅授权修订：页面只订阅同版本扫描；区分上次成功与当前进度，覆盖取消、部分失败与迟到事件。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

### 需求修订（2026-10-17T23:15:20+08:00）

- 授权：用户要求按架构质量、设计完整性和技术债修复全部待办 task；本次仅修订目标文档，尚未实施。
- 决策与追溯：把接上扫描明确为服务统一所有权，移除页面名单备用通道；补齐订阅取消、部分失败、尾批发布及旧版本拒收。
- AC 变更：保留 AC-001～AC-006 的行为归属并补边界；新增 AC-007～AC-009。

### 实施记录（2026-10-18T00:35:00+08:00）

- 架构收敛：`BackgroundScanService` 作为名单扫描唯一所有者，移除页面私有扫描与接管分支；`BackgroundScanProviding` 暴露 `inProgressUninstallList()` 与 `waitForScan()`。
- 渐进聚合与尾批交付：`BackgroundScanService.run` 实现流式行的 100 ms 聚合与尾批延迟交付；在途进度与最后成功快照严格分离。
- 页面订阅与安全隔离：`UninstallViewModel` 与 `InstallersViewModel` 订阅扫描服务状态并同步进度；流式未完成前 `canUninstall` 为 `false`；流式失败或取消清空临时行，旧成功快照与 `capturedAt` 完整保留。
- 测试：新建 `PrewarmPageAttachTests.swift`（4 个用例），全量 318 个 Swift 单元测试、147 个模板契约测试、3 个集成测试全绿。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-10-18T00:35:00+08:00)

Round 1 零 finding。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'`（318 passed）+ `pytest .repo_template/tests -q -m contract`（147 passed）+ 3 条集成测试脚本通过
- 黑盒：`xcodebuild test -scheme Zmole -destination 'platform=macOS' -only-testing:ZmoleTests/StatusStreamTests`（通过）
- review：`docs/tasks/t049_prewarm_page_attach/review_code.md` 与 `review_test.md`（PASS，round 1，coverage 100%）
- AC 证据：见 `handoff.json`

### 结果摘要

- 统一了名单扫描所有权与页面订阅，实现了 100 ms 尾批交付、流式未完成保护和多订阅者并发隔离。无遗留问题。
