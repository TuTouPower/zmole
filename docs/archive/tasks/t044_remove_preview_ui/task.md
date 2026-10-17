---
tid: "t044"
slug: "remove_preview_ui"
title: "去预览化页面与卸载步骤简化"
status: "done"
branch: "t044_remove_preview_ui"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "865a07b94b9ebe2a6a3ad5e7b3949822278e43e8"
depends_on: "t043"
conflicts_with: ""
note: "用户 2026-10-17 批准：用户可见预览全部改刷新/后台数据；卸载页去掉预览步骤；破坏性确认保留。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- 清理、优化、项目清理三页去预览化：ViewModel 移除本地 `--dry-run` 预览进程与 `CleanPreviewStore` 校验，直接消费 `BackgroundScanProviding` 缓存结果并在页面打开时自动填充；页头动作改为「刷新」（`clean.refresh`/`optimize.refresh`/`purge.refresh`），扫描进行中变为「取消」并委托 `cancelAndWait`；空态在扫描中显示刷新状态、无数据时显示刷新引导，失败时展示重试。
- 破坏性确认保护：三页执行门禁由「已完成成功预览」改为「有后台扫描结果即可确认」，点击打开原有 `DestructiveConfirmationView`；取消不执行且保留页面数据；clean 执行不再校验 `clean-list.txt` 同长度未变，并在执行前停止后台 clean 扫描。
- 卸载流程简化：选中应用后「卸载…」直接打开确认 sheet，彻底删除「预览卸载」与底部「预览结果」浮层；保留「检查关联文件」作为按需排查；确认时执行轻量目标身份复核，不符时拒绝并重扫名单。
- Demo 与全装配补全：为 demo 装配完整的 `BackgroundScanLanes` 与演示目录临时缓存，三页在 demo 下由 `DemoMoleProcess` 产出数据；`DemoUninstallTargetChecker` 放行演示虚拟路径；`cleanBusyProvider` 仅在 `isConfirmationPresented || isExecuting` 时置位，解决预览常驻导致刷新被永久 defer 的缺陷。
- 全量本地化重整：三语清除全部用户可见「预览/preview」，更新相关说明文案；删除未引用的死 key（`clean.preview_*`、`clean.stage.*`、`optimize.preview_*`、`purge.preview_*`、`uninstall.preview*` 等）；`UiAlignmentTests` 增加全 string-catalog 禁词扫描守门。
- 测试重构说明：删除旧的本地 dry-run 预览用例（`CleanPageTests` streaming/cancel、`OptimizeTests` dry-run/previewFailure、`PurgeTests` 同型用例、`ZmoleTests` clean 预览用例），在同层补充后台扫描采用、自动填充、刷新委托与确认执行用例；`UninstallTests` 调整为直接确认与身份核对断言。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-10-17T19:49:10+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t044_code_f001|important|已修|为 demo 装配 BackgroundScanLanes 与独立缓存，使三页在 demo 模式下产出数据并可刷新|src/zmole/App/MoleCommandLanes.swift:125|
|t044_code_f002|minor|已修|移除 CleanViewModel 与 UninstallViewModel 中未使用的 previewID 绑定|src/zmole/Features/Clean/CleanViewModel.swift:120|
|t044_code_f003|minor|已修|CleanView 扫描态改用 clean.refreshing，Localizable.xcstrings 移除未引用的 clean.scanning|src/zmole/Features/Clean/CleanView.swift:141|
|t044_code_f004|minor|已修|docs/specs/overview.md 补全健康卡可回收量来源与无数据显示契约|docs/specs/overview.md:12|
|t044_code_f005|minor|已修|BackgroundScanProviding 扩展 observeStateChanges 消除两处 ViewModel 的订阅样板重复|src/zmole/Features/Operations/BackgroundScanService.swift:57|
|t044_test_f001|important|已修|cleanBusyProvider 解绑 preview != nil，改为 ownsCleanListFile，并补单元测试防回归|src/zmole/Features/Clean/CleanViewModel.swift:46|
|t044_test_f002|minor|已修|CleanPageTests 补充 testCancelConfirmationKeepsTheScanAndDoesNotExecute 取消不执行用例|tests/unit/CleanPageTests.swift:171|
|t044_test_f003|minor|已修|CleanPageTests 补充 testRefreshingStateFollowsTheBackgroundScan 断言扫描中与刷新取消|tests/unit/CleanPageTests.swift:188|
|t044_test_f004|minor|已修|移除 ZmoleTests 中未引用的 CleanSpyWaitError 死代码枚举|tests/unit/ZmoleTests.swift|

### Round 2 (2026-10-17T20:20:00+08:00)

Round 2 零 finding（代码轴 PASS，测试轴 PASS）。

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`xcodegen generate`；`xcodebuild test -scheme Zmole -destination 'platform=macOS'` 292 用例 0 失败；`xcodebuild build -configuration Release` 通过；`pytest .repo_template/tests -q -m contract` 147 通过；`tests/integration/clean_trash_test.sh`、`installer_interface_test.sh`、`uninstall_stream_test.sh` 全部通过；`git diff --check` 干净
- 黑盒：运行构建出的 Zmole Debug，在清理、优化、项目清理各页验证直接展示数据、页头为「刷新」、无任何「预览」字样，Demo 模式启动正常展示数据；命令行 `ps` 确认无遗留孤儿进程
- review：full；code PASS（rounds 1-2）、test PASS（rounds 1-2）、`check_review_status.py overall=PASS review_scope=ok`、`reviewed_scope 7e7dac6b84097548`
- AC 证据：见 `handoff.json`

### 结果摘要

- 清理、优化、项目清理与卸载页全面去除用户可见预览，改为直接展示后台扫描数据，按钮统一为「刷新」；卸载页直接弹出确认并执行；保留破坏性操作确认弹窗与关联文件检查。
- 遗留：无。
