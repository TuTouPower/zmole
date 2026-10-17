---
tid: "t040"
slug: "overview_estimate_and_head_polish"
title: "概览存储估算修复与页头卡片清理"
status: "done"
branch: "t040_overview_estimate_and_head_polish"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "c4a338897084ae66378113b0e88061f9c4f3e397"
depends_on: ""
conflicts_with: ""
note: "用户 2026-10-17 批准（来源 p013；含去页头 eyebrow 小字与概览四卡等高）"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- 估算重构：`OverviewViewModel` 以 VM 持有任务解耦视图生命周期；`startEstimate` 不等 status 采样；`runEstimate(fillMissingOnly:isFollowUp:)` 区分全量/补缺；失效或 TTL 过期一律全量；完成（含部分）即展示并落盘；不完整时安排一次补扫（只探缺失段，`incompleteRetryDelay` 可注入）；fill-only 沿用旧 `capturedAt` 防 TTL 续命；扫描期间落下的失效使补扫升级为全量。`StorageEstimateLoader.loadSums(filling:)` 支持只探缺失段；估算通道超时 120→600（`AppDependencies`）。
- 页头清理：`MolePageHead` 移除 `eyebrow` 参数（9 个调用点同步）；健康卡去掉「整体状态」小字；catalog 删除 11 个 eyebrow 键。
- 概览四卡统一固定高度（`OverviewCardLayout.cardHeight = 264`），1200×780 与 1100×700 截图核对无裁切。
- 文档同步：`architecture.md`/`domain.md`/`ui_contract.md` 与 `docs/specs/overview.md`、`app_shell.md`。
- p013 已由本 task 闭环归档（`pending.py archive --fix-ref t040`）；review 发现「扫描在飞期间失效且完整结束」的窄窗口补偿缺口，登记 p014。
- 验证：`xcodebuild build` 0 error；全量 `xcodebuild test` 279 例全绿（含新增 6 条估算用例）；黑盒 demo 启动截图核对（无 eyebrow、四卡等高、暗色/最小窗口）。
- 无用户批准的新轮次上限（3 轮 review 在 review_limit 内）。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-10-17T13:40:00+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t040_gen_f001|important|已修|失效/TTL 触发改为全量重扫（第二轮补全 TTL/capturedAt 链路，见 Round 2）|OverviewViewModel.swift startEstimate/runEstimate|
|t040_gen_f002|minor|已修|`.task` 先 prime/start 再 await refreshHistory|OverviewView.swift:45-52|
|t040_gen_f003|minor|已修|补扫统一在完成点调度，先判 incomplete，`isEstimating` 防重入|OverviewViewModel.swift scheduleIncompleteRetry|
|t040_gen_f004|minor|已修|新增 600s 源码断言用例|tests/unit/OverviewCacheTests.swift testEstimateLaneTimeoutIsTenMinutes|
|t040_gen_f005|minor|已修|caller 挂起期间取消 + ScanGate 超时 XCTFail|tests/unit/OverviewCacheTests.swift|

### Round 2 (2026-10-17T14:20:00+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t040_gen_f006|minor|遗留|补扫升级已修；「在飞扫描期间失效且完整结束」的补偿缺口窄窗口、最终一致（下次概览触发全量），登记跟进|p014|

Round 2 复核记录（非新 finding）：f001 修复不彻底（TTL/capturedAt 链路未闭合），已在 Round 3 前补修并由 Round 3 复核消除；f002–f005 未回退。

### Round 3 (2026-10-17T14:45:00+08:00)

Round 3 零 finding（f001 已消除、f002–f005 未回退；f006 残余维持 minor 遗留 p014）。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足（AC-001–AC-009；AC-009 以源码断言 + 1200×780/1100×700 demo 截图核对）
- 测试：`xcodebuild build` 0 error；全量 `xcodebuild test` 279 例 0 失败（含新增用例）；`git diff --check` 干净
- 黑盒：demo（不启动真实 mole）逐页启动 + 概览截图核对：无 eyebrow 小字、四卡等高、浅色/深色/最小窗口无裁切；TCC 首启提示为系统行为，已逐个处置
- review：`review_general.md` Round 3 verdict PASS（coverage 8/9，AC-009 trust_prior + 实施侧截图）
- AC 证据：见 `handoff.json`

### 结果摘要

- 估算触发/持久化语义按 t040 spec 落地：进入概览即扫描、部分即展示并落盘、只补缺失段一次、失效/TTL 全量、取消不落盘、通道超时 600s；页头 eyebrow 全量移除、概览四卡等高。
- 遗留：p014（在飞失效 + 完整结束的窄窗口补偿）；无其它遗留。
