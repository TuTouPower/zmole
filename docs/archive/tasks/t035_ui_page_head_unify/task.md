---
tid: "t035"
slug: "ui_page_head_unify"
title: "UI 对齐 demo：页头、状态页、历史页与说明条"
status: "done"
branch: "t035_ui_page_head_unify"
worktree: ""
review_level: "single"
review_limit: "5"
verify_limit: "5"
diff_anchor: "02db874621bd1484e6f5d87caa9043003455500f"
depends_on: ""
conflicts_with: "t028"
note: "用户 2026-10-17 批准（原 t035；合并 t037/t038/t039）。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- 共享组件：`MolePageHead`（eyebrow+标题+副标题+右侧动作区，对齐 demo `.page-head`）与 `MoleStatTile` 加入 `UtilityUI.swift`；`MoleTheme` 增加 `blueSoft`/`blue`（浅色取 demo `#eaf1ff`/`#355b99`，深色取可辨蓝，demo 深色媒体查询未覆盖 info-banner 文字色）；`UtilityNotice` 增加 `isInfo` 与 `NoticeTone`（error 优先）。
- 五页接入页头：卸载（刷新应用列表／进行中显示取消）、磁盘（返回上级＋再次分析，排序下拉移入搜索行）、状态（采样指示＋暂停/恢复＋刷新）、历史（导出 JSON＋刷新）、设置（无动作）。卸载与历史的窗口 `.toolbar` 重复入口删除；概览/清理/优化/项目清理/安装包既有页头未动（非范围）。
- 状态页重排：页头 → 4 格指标条（CPU/内存/磁盘写入/温度，缺失显示占位、warming 显示采样中不显示 0）→ 系统负载图卡（最近 60 秒 CPU+内存，`StatusChart` 纯函数：窗口裁剪、\<2 采样不画线只显示等待）与网络卡并排 → 进程表（只读、陈旧标记、僵尸徽标）。磁盘容量/读写/温度原独立面板并入指标条。
- 历史页：`HistoryTable` 纯函数生成四列表格行（session：日期/命令/条目·容量/已完成；deletion：时间戳/路径/容量/原状态）；删除路径中部截断＋悬停全路径＋可选中；状态本地化在视图层解析（避免 `String(localized:)` 落系统语言）；空状态保留；导出行为不变（入口移至页头）。
- 说明条：优化/项目清理/历史改用蓝色 info-banner；错误与危险提示不变（测试断言 permanent_note 仍 isError）。
- `docs/design/ui_contract.md` 页工具栏条目更新为「页面动作位于页头右侧」。
- 测试：新增 `UiAlignmentTests`（图表几何/窗口/边界，指标条占位与 warming，历史表格映射与占位，NoticeTone 映射，五页页头接入与 toolbars/banners 源码断言）；257 例通过。
- 黑盒：status 浅色 zh（指标条/负载图/网络/进程）、history 深色 en（四列表格＋蓝色说明条）、disk 浅色 zh（页头＋返回禁用＋再次分析＋排序移入搜索行）、optimize 浅色 zh（信息条变蓝、永久删除红条不变）、uninstall 浅色 zh（页头＋刷新动作、无窗口工具栏重复）截图核对。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-10-17T03:50:00+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t035_gen_f001|minor|已修|删除零引用的 `UtilityToolbar` 与 `UtilityMetric`|src/zmole/Features/UtilityUI.swift|
|t035_gen_f002|minor|已修|删除 25 个随旧 UI 退休的本地化键（含未用的 analyze.subtitle）；原 status detail 键测试更新为新指标条键（旧键随旧卡片移除，测试意图不变）|src/zmole/Resources/Localizable.xcstrings / tests/unit/ZmoleTests.swift|
|t035_gen_f003|minor|撤回|五页页头/说明条为 SwiftUI 视图层布线，单测只能做源码存在性断言；spec 可测试性声明已授权视图层替代验证，仓库既有同类先例（DiskExplorerTests/AppIconTests 源码断言），非本 task 引入的新模式|tests/unit/UiAlignmentTests.swift|

### Round 2 (2026-10-17T04:00:00+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t035_gen_f004|minor|已修|补删 7 个零引用残留键（status.trend_ready、uninstall.refresh、analyze.refresh、history.deletions/items/sessions/size）；旧键测试就地改键改为改名+注明新旧关系（testStatusStatKeysHaveLocalizedValues）|src/zmole/Resources/Localizable.xcstrings / tests/unit/ZmoleTests.swift|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足（24/24 AC；视觉类 AC 按 spec 可测试性声明以 demo 截图对照 + 视图层源码断言验证）
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` 257 通过（新增 UiAlignmentTests）；`pytest .repo_template/tests -q -m contract` 147 通过；三组 shell 集成通过
- 黑盒：demo 截图核对 status 浅色 zh（4 格指标条/60 秒负载图/网络/进程，头与动作）、history 深色 en（四列表格、日期单行、状态本地化、蓝色说明条）、disk 浅色 zh（页头、返回禁用、再次分析、排序移入搜索行）、optimize 浅色 zh（说明条蓝色、永久删除红条不变）、uninstall 浅色 zh（页头+刷新应用列表、无窗口工具栏重复）
- review：single Round 3 PASS（`review_general.md`）；`reviewed_scope ab1c1ac69afaccc5`；无未解决 finding
- AC 证据：见 `handoff.json`

### 结果摘要

- 共享 `MolePageHead`/`MoleStatTile` 落地，卸载、磁盘、状态、历史、设置五页接入页头并把页面动作移入右侧；卸载/历史窗口工具栏重复入口移除；概览等五页既有页头未动。
- 状态页重排为页头→4 格指标条→负载图+网络→进程表；负载图仅在有 ≥2 采样时绘制，采样不足显示等待；指标缺失显示占位。
- 历史页改为对齐四列表格（session/deletion 两类），删除路径中部截断+悬停+可选中；空状态与导出不变。
- 优化/项目清理/历史说明条改为蓝色 info-banner；错误与危险样式不变；`ui_contract.md` 页工具栏条目同步。
- 遗留：无
