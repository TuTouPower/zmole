---
tid: "t026"
slug: "overview_storage_estimate_cache"
title: "概览磁盘估算缓存与后台刷新"
status: "done"
branch: "t026_overview_storage_estimate_cache"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "ec8bfbf37a782d1b3227cfd1aea7fca289fcd886"
depends_on: "t025"
conflicts_with: ""
note: "开屏用缓存即时显示，后台刷新。来源 p007。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

来源：`p007`（2026-10-16 核实；用户修订：不做按钮）。

- 新增 `StorageEstimateCache`（App 容器下 `storage_estimate.json`，schemaVersion/capturedAt，原子写，TTL 6h / 最大年龄 7 天）；`StorageEstimate.swift` 增 `StorageSums`(Codable) + `loadSums()`。
- `OverviewViewModel` 增缓存/coordinator/clock：`primeEstimate` 先渲染缓存、`refreshEstimateIfNeeded` 仅在缺失/过期/失效时后台重算、`estimateNeedsRefresh`、`estimateInvalidated`（含 mid-scan 失效保留）；部分缓存不抑制重试。
- `OverviewView` 先 prime 再后台刷新，并监听失效；`AppDependencies` 传 `.live` 缓存（demo 为 nil）。
- `docs/blueprint/architecture.md` 更新估算缓存与刷新口径。
- 测试 `tests/unit/OverviewCacheTests.swift` 覆盖 6 条 AC 与两个回归（mid-scan 失效、部分缓存重试）。

## Review 处置

review_level=single（`review_general.md`）。

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t026_gen_f001|minor|已修|mid-scan 失效被清空，改为计数比对保留|OverviewViewModel.swift|
|t026_gen_f002|minor|已修|不完整缓存按新鲜处理，改 isComplete 强制重试|StorageEstimate.swift / OverviewViewModel.swift|
|t026_gen_f003|minor|撤回|mid-scan 失效保留但不自动再排一次；下次触发/进入概览会重算，非阻断|OverviewViewModel.swift|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'`：193 tests / 0 failures；`pytest .repo_template/tests -q -m contract`：147 passed
- 黑盒：GUI 受限（同前）；缓存/新鲜度/失效/部分失败由假 analyze + 临时缓存 + 假时钟覆盖
- review：`review_general.md` rounds 1-2 最终 PASS
- AC 证据：见 `handoff.json`

### 结果摘要

- 概览五段估算改为缓存优先即时渲染、后台按 TTL/写入失效刷新，在独立只读通道执行；无手动按钮；部分失败段占位且可重试。遗留：一个 minor（mid-scan 失效重排）已撤回。
