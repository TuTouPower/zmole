---
tid: "t025"
slug: "command_concurrency_lanes"
title: "命令并发通道按类型区分"
status: "done"
branch: "t025_command_concurrency_lanes"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "156c58d3f779f9e3562e1f727c0fe1e7c9d50127"
depends_on: ""
conflicts_with: ""
note: "只读命令可并发、写入串行、长驻流独立。来源 p006。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

来源：`p006`（2026-10-16 核实）。用户实测 `analyze --json /` 约 2m41s 阻塞其它页面。

- 新增 `MoleCommandLanes`：9 条一次性通道（analyze/history/uninstall/installer/statusCommand/cleanCommand/optimize/purge/estimate）+ statusStream + cleanStream；提供 `makeCommandBridges`、`.demo`、`.unavailable`。
- `AppDependencies` 按通道装配，各功能页/loader 使用各自 lane；写入仍由 `OperationCoordinator` 单一租约互斥。`AppDependencies.lanes` 暴露供装配断言。
- `UnavailableMoleProcess/Streaming` 改为 internal 供 lanes 复用。
- `docs/blueprint/architecture.md` 更新命令并发通道分类。
- 测试 `tests/unit/CommandConcurrencyTests.swift`：桥互不 busy、流不阻塞、写入 VM 互斥、同桥重复提交 busy、生产装配 9 条 lane 互异。

## Review 处置

review_level=full：`review_code.md` / `review_test.md`。

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t025_code_f001|minor|撤回|陈旧注释，无行为影响|StorageEstimate.swift / OverviewView.swift|
|t025_code_f002|minor|撤回|概览与历史共用只读 history lane，同时只可见一页，接受|MoleCommandLanes.swift|
|t025_code_f003|minor|已修|补生产装配 lane 互异与写入 VM 互斥用例|CommandConcurrencyTests.swift|
|t025_code_f004|minor|已修|waitUntilBusy 改 XCTFail|CommandConcurrencyTests.swift|
|t025_code_f005|minor|撤回|AC-004 用例标签措辞，无功能影响|CommandConcurrencyTests.swift|
|t025_test_f001|important|已修|补 AppDependencies 装配与 MoleCommandLanes 断言|CommandConcurrencyTests.swift|
|t025_test_f002|minor|已修|消除 XCTSkip fail-open|CommandConcurrencyTests.swift|
|t025_test_f003|minor|已修|补跨 lane 写入 VM 互斥端到端用例|CommandConcurrencyTests.swift|
|t025_test_f004|minor|撤回|AC-003 用假进程，AC-001/002 用真实 sleep 作机制证明|CommandConcurrencyTests.swift|
|t025_test_f005|minor|撤回|流 lane 唯一性未单测；流各由单一消费者持有，AC-002 已覆盖流不阻塞|CommandConcurrencyTests.swift|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'`：184 tests / 0 failures；`pytest .repo_template/tests -q -m contract`：147 passed；两个 bash 集成测试通过
- 黑盒：GUI 受限（同前）；并发/互斥由真实桥与假进程自动覆盖
- review：`review_code.md`（rounds 1-2）、`review_test.md`（rounds 1-2）最终均 PASS
- AC 证据：见 `handoff.json`

### 结果摘要

- 命令按类型分通道：每个一次性消费者独立 bridge，流独立；写入由 coordinator 租约互斥。慢 analyze 不再阻塞其它页面。遗留：两个 minor 覆盖 nit 已撤回。
