---
tid: "t036"
slug: "ui_overview_align"
title: "概览页重排与存储估算修复"
status: "done"
branch: "t036_ui_overview_align"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "72fbd36a15c3f7491806384dbdf84f2410a66abd"
depends_on: ""
conflicts_with: ""
note: "用户 2026-10-17 批准（原 t036；合并 t034 的估算修复，系统段只计只读系统卷）。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- 概览重排：页头（eyebrow/问候语/副标题）右侧动作＝刷新（`statusViewModel.retry()` 触发重采样）与清理入口（`navigation.select(.clean)`，容量取 `CleanViewModel.lastReclaimBytes`，无数据显示纯入口文案）；健康卡改为 demo 结构（圆环健康分+状态文案+三指标 tile：可用磁盘/可回收/CPU，缺失占位）；存储卡改为大数字已用+五段分段条+图例（自由空间段单独配色）；下半区＝最近活动（icon+命令+时间+容量+项数，查看历史入口）与系统状态四宫格（CPU/内存/温度/网络，缺失占位）；快捷卡与趋势条移除（连同 `OverviewQuickAction`/`OverviewTrend`/环形图/柱条视图）。纯映射抽为 `OverviewHealthCard`/`OverviewStatusGrid`/`OverviewActivity`/`OverviewStorageCard` 供单测。
- 估算修复（p012）：`StorageEstimateLoader` 改为 throwing：取消（`CancellationError`/bridge cancelled）与失败区分；系统段按 `/System` 顶层子项逐项 `analyze`，跳过 `/System/Volumes`（数据卷 1.4TB 不再进入扫描，秒级），值＝analyze /System 顶层排除 Volumes 之和；`computeEstimate` 仅在四路径齐全时落盘并接替展示，取消或不完整不写缓存不替换（历史部分缓存仍先渲染、随后完整扫描覆盖）。
- demo fixture：`/System/*` 子项与 `/System/Volumes` 补充分析夹具，避免 demo 系统段被默认夹具放大。
- 测试：`OverviewCacheTests` 更新（不完整扫描不落盘不渲染、取消不落盘、部分缓存先渲染后被完整覆盖、不探测 Volumes、失效守卫），`OverviewTests` 删除趋势/快捷卡用例（类型移除）并迁移 loader 用例，新增 `OverviewLayoutTests`（健康卡/状态四宫格/活动行/存储卡映射与占位、无快捷卡趋势的源码断言）；268 例通过。
- 黑盒：demo 概览浅色 zh 与深色 en 截图核对（页头动作、健康环、存储分段条与图例、最近活动、系统状态四宫格；无快捷卡/趋势条）。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-10-17T04:45:00+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t036_gen_f001|important|已修|系统段任一目录子项探测失败即整段不可用（不落盘、不替换、下次重试）；`systemChildren` 只列目录；新增「一子项失败、另一子项成功→segment nil」用例|src/zmole/Features/Overview/StorageEstimate.swift|
|t036_gen_f002|minor|已修|新增 `StatusViewModel.resample()`（pause+start 强制重订阅取新采样），概览刷新按钮改用它并补单测|src/zmole/Features/Status/StatusViewModel.swift|
|t036_gen_f003|minor|已修|活动行 id 改为稳定序号（activity-N），纳入行索引避免重复 id|src/zmole/Features/Overview/OverviewViewModel.swift|
|t036_gen_f004|minor|已修|删除未用 `import SwiftUI` 与 `overview.memory` 键；`memoryText` 由四宫格复用（消除重复格式化）|src/zmole/Features/Overview/OverviewViewModel.swift|
|t036_gen_f005|minor|已修|architecture.md 改为「三次固定 analyze + 系统段按目录子项逐项 analyze（跳过 /System/Volumes，任一失败段不可用）」|docs/blueprint/architecture.md|

### Round 2 (2026-10-17T04:55:00+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t036_gen_f006|minor|已修|architecture.md「最近操作」段删除已移除的概览趋势条描述，改指状态页负载图的等待语义|docs/blueprint/architecture.md|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足（12/12 AC；视觉类 AC 以 demo 截图对照 + 视图层断言验证）
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` 270 通过；`pytest .repo_template/tests -q -m contract` 147 通过；三组 shell 集成通过
- 黑盒：demo 概览浅色 zh 与深色 en 截图核对：页头动作（刷新/清理）、健康环与三 tile、存储大数字+分段条+图例、最近活动行、系统状态四宫格；页面已无快捷卡与趋势条
- review：single Round 3 PASS（`review_general.md`）；`reviewed_scope a8575a3f3074ffd8`；无未解决 finding
- AC 证据：见 `handoff.json`

### 结果摘要

- 概览按 demo 重排：页头动作（刷新=强制重订阅取新采样、清理入口跳转且带可回收容量）、健康卡（圆环+状态文案+可用磁盘/可回收/CPU）、存储卡（已用大数字+五段分段条+图例+不完整提示）、最近活动与系统状态四宫格；快捷卡与趋势条移除。
- 估算修复：系统段只计只读系统卷（按 /System 顶层目录子项逐项 analyze、跳过 /System/Volumes，任一子项失败整段不可用）；取消或不完整的扫描不落盘、不替换权威展示；历史部分缓存先显示、随后完整扫描覆盖。
- 遗留：无；另：评审发现 `.repo_template/scripts/repo_task/review.py` 的 `reported_findings()` 与模板标题格式不匹配（`missing_disposition` 检查失效），属模板工具链缺陷，已按约定上报用户处理，未自行修改。
