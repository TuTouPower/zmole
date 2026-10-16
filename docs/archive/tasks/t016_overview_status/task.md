---
tid: "t016"
slug: "overview_status"
title: "概览首页与状态页"
status: "done"
branch: "t016_overview_status"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "43243a5d0d7b3bc9d8f832717358f7a792358de6"
depends_on: "t015"
conflicts_with: ""
note: "概览真实采样、五段估算、状态页。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

来源：docs/design/refactor_grilling.md。用户于 2026-10-16 批准后创建。

- 新增 `StorageBreakdown` 五段公式 + `StorageEstimateLoader`（四次 analyze 目录求和，串行）；`OverviewMetrics`、`OverviewTrend`、`OverviewQuickAction`、`OverviewViewModel`；重写 `OverviewView`（健康分/CPU/内存/可用磁盘、五段环、快捷卡、最近操作、趋势）。
- `StatusSnapshot` 增加 `cpuTemperature`（thermal.cpu_temp）与 `zombieCount`；`StatusView` 增温度/僵尸面板；新增 `StatusReadout` 统一缺失值显示“未知”。
- `AppShellView` 按目的地统一 start/stop 共享 status watch；`SidebarView` 状态项在采集中显示圆点。
- 关键决策：`MoleBridge` 单 active runner，常驻 status watch 与一次性命令冲突。App 装配改为两条独立 `MoleBridge`（流式 = status watch；一次性 = analyze/history/预览等）。概览的五段估算串行执行，且在 history 之后、首次拿到已用空间时只加载一次（无逐 tick 重算）。
- `DemoMoleProcess`/`DemoMoleStreaming` 夹具改为按路径返回 analyze，并补 thermal/zombie 字段。
- 黑盒：同 t015，GUI demo smoke 受执行环境限制无法取得窗口；已用自动化门禁（121 单测含注入夹具）替代，见 t015 实施笔记。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-10-16T17:57:26+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t016_gen_f001|important|已修|watch 与一次性命令共用单 bridge 互斥，拆为两条独立 bridge|AppDependencies.swift|
|t016_gen_f002|important|已修|估算绑定 collectedAt 逐 tick 重算，改为一次性触发|OverviewView.swift|
|t016_gen_f003|minor|已修|网络缺失改显示“未知”|StatusReadout.swift|
|t016_gen_f004|minor|已修|补 AC-006/AC-007 断言|OverviewTests.swift|
|t016_gen_f005|minor|已修|概览重复 start 移除，watch 生命周期交给壳|OverviewView.swift|
|t016_gen_f006|minor|已修|refresh 加重入保护|OverviewViewModel.swift|

### Round 2 (2026-10-16T18:02:00+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t016_gen_f007|important|已修|四次 analyze 并发共用命令 bridge，改为串行|StorageEstimate.swift|
|t016_gen_f008|minor|已修|architecture.md 两条 bullet 合并，已拆开|architecture.md|
|t016_gen_f009|minor|已修|单 bridge 兜底会重现争用，已移除|AppDependencies.swift|

### Round 3 (2026-10-16T18:06:00+08:00)

Round 3 verdict PASS；新 finding 两条 minor。

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t016_gen_f010|minor|撤回|首帧已用空间等待上限 12s，超时则本次不估算是可接受取舍，非 spec AC|OverviewView.swift|
|t016_gen_f011|minor|撤回|跨页短暂 busy 属单命令 bridge 的既有语义，后续命令级排队作为长期架构项，不在本 task|AppDependencies.swift|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'`：121 tests / 0 failures；`pytest .repo_template/tests -q -m contract` 见下
- 黑盒：GUI demo smoke 受执行环境限制无法取得窗口（同 t015）；状态只读 watch 由 StatusStreamTests 自动化覆盖
- review：`review_general.md` three rounds，最终 verdict PASS；f001/f002/f007 等 important 全部修复
- AC 证据：见 `handoff.json`

### 结果摘要

- 概览首页接入真实 status（健康分/CPU/内存/可用磁盘/趋势）+ 五段目录估算 + history 最近操作；状态页补温度与僵尸进程，缺失显示未知；watch 按页面生命周期启停，侧边栏状态项显示采集圆点。遗留：t010/t011 两条 minor 已撤回（可接受取舍）。
