---
tid: "t029"
slug: "uninstall_list_progressive"
title: "名单复用与空闲预跑"
status: "done"
branch: "t029_uninstall_list_progressive"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "ab664ca5f9ba3a484abad7a3c1c0056123e82534"
depends_on: "t028"
conflicts_with: ""
note: "用户 2026-10-17 批准（原 t029；合并 t030/t031）。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

- CLI：`uninstall.sh` 新增 `--list-stream`（JSONL：先身份行、后完整行、末 `{"event":"done"}`；身份行经 fd 3 流出，避免与 `scan_applications` 的 stdout 路径捕获冲突）。完整行的版本读目标自身 `Info.plist`（无 Spotlight），上次使用取本次扫描的 epoch；大小 N/A 保持未知。`installer.sh --remove` 不再重扫扫描根：只做目标自身复核（仍在扫描根内、深度 ≤ 扫描深度、候选扩展名/zip 载荷、大小与 identity 未变），另加 `MOLE_INSTALLER_SCAN_DISABLED` 集成测试钩子证明删除路径不重扫。该行为变化同步更新了 `installer_interface_test.sh`（新增 t029 两例，原有 AC 全保留）。
- 卸载名单侧：新增 `UninstallListStream` + `UninstallAppListing`（渐进行，later-row-wins）+ 解析器；`UninstallViewModel` 重写为流式合并，列表先出、大小/版本随后；Spotlight 元数据提供者删除，版本/上次使用随行携带；确认改用 `UninstallTargetChecking` 轻量核对（路径存在 + bundle id 未变），不再二次 `--list`；身份变化拒绝并重扫名单（保留失败展示）。图标改为异步 `UninstallIconProviding`，列表先可交互、图标随后补上。`UninstallApp.id` 改为 path（渐进阶段稳定），新增 version/lastUsed 字段。
- 安装包侧：`loadListIfNeeded` 会话复用；删除逐文件复核仍在当前会话名单内（`installers.error.not_listed`）。CLI 删除不再遍历扫描根。
- 预跑：新增 `PrewarmService`（Features/Operations）：固定顺序 卸载名单→安装包名单→clean/optimize/purge dry-run；单 worker、单 lane、不取写入租约；空闲 = 无租约且无外部活动（磁盘扫描、卸载/安装包名单扫描、正在查看的清理预览）；写入开始取消当前项、写入成功（invalidatePreviews）清空结果并重排队列；失败项跳过并在下一次空闲重试；用户重扫取消当前项并丢弃；结果带 `capturedAt` 供页面标注扫描时间；generation 守卫防止作废后的迟到结果落盘；清理项在用户持有预览时延后。`MoleCommandLanes` 增加 `uninstallStream` 与 `prewarm` 通道；`AnalyzeViewModel.isScanning` 供空闲判定。demo 不建预跑（`prewarmService == nil`），卸载名单由 `DemoUninstallListStream` 分阶段产出以展示渐进态。
- 页面：清理/优化/项目清理在 `.task` 采纳预跑结果（仅当无本地预览）；卸载/安装包打开页面优先采纳预跑名单；各页显示扫描时间。
- 测试：套件 233 例通过。新增 `PrewarmTests`（顺序/互斥/无租约/写入取消/作废重跑/用户重扫/失败重试/磁盘扫描与清理预览阻塞/demo 禁用/各页采纳/确认保护）、`UninstallStreamTests`（渐进行先于大小、图标后到、解析器边界）。原卸载测试从「列表走 process」迁移到「列表走注入流」，原「changed path / missing target 重扫列表」两例合并为注入 target checker 的拒绝+重扫例（理由：路径缺失与身份变化在轻量核对下是同一拒绝路径）。

## Review 处置

每个结构化 finding 一行。`已修` 表示本 task 已修复；`遗留` 必须指向 `pNNN` 或 follow-up tid；`撤回` 必须写清理由。critical/important 未解决时不得 PASS。

### Round 1 (2026-10-17T03:00:00+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t029_code_f001|important|已修|空闲合并去重（retries 优先、队列剔除同项），被取消项只重跑一次|src/zmole/Features/Operations/PrewarmService.swift|
|t029_code_f002|important|已修|`AnalyzeViewModel.isScanning` 改为 `@Published`，list/worker 起止刷新，磁盘测量结束可见|src/zmole/Features/Analyze/AnalyzeViewModel.swift|
|t029_code_f003|minor|已修|clean 预跑跳过条件并入用户预览进行中（`isPreviewing`）|src/zmole/App/AppDependencies.swift|
|t029_code_f004|minor|已修|采纳 reviewer 建议改 spec：AC-005 与范围只核对路径+bundle id，卸载名变化由命令失败暴露|docs/tasks/t029_uninstall_list_progressive/spec.md|
|t029_code_f005|minor|已修|删除零引用：`UninstallListSnapshot`、`UninstallPreviewSnapshot.identities`、`UninstallListDecoder`（测试改 JSONDecoder）、`UninstallListFilter.visible`（测试改 visibleListings）、`PrewarmItem.commandArguments`|src/zmole/Features/Uninstall/UninstallSnapshot.swift|
|t029_code_f006|minor|已修|`performList` 收尾按本次流到的 path 裁剪 listings/selection/related/icons|src/zmole/Features/Uninstall/UninstallViewModel.swift|
|t029_code_f007|minor|已修|删除同分支三元，统一 `.secondary`|src/zmole/Features/Uninstall/UninstallView.swift|
|t029_code_f008|minor|已修|提取 `UninstallListMerge` 供 VM 与预跑共用|src/zmole/Features/Uninstall/UninstallListStream.swift|
|t029_test_f001|important|已修|新增 `UninstallTargetCheckerTests`：路径缺失/身份相同/身份变化/空 bundle id 四分支|tests/unit/UninstallTargetCheckerTests.swift|
|t029_test_f002|important|已修|删除不可达的逐文件守卫；测试改为断言选择始终来自会话名单、重扫后不可删除|tests/unit/InstallersPageTests.swift|
|t029_test_f003|important|已修|新增 `UninstallStreamingAssemblyTests`（`init(streaming:)` 装配解析）与 `tests/integration/uninstall_stream_test.sh`（真实脚本 + `MOLE_UNINSTALL_SCAN_ROOT` fixture 根），登记进 testing.md test_cmd；Prewarm 顺序测试补 uninstallList 结果断言，并新增取消重排 exactly-once 回归|tests/unit/UninstallStreamTests.swift / tests/integration/uninstall_stream_test.sh|

### Round 2 (2026-10-17T03:20:00+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t029_code_f009|important|已修|`performList` 改为以本次扫描结果整体替换 `listings`（局部合并后赋值），重扫不再追加重复行；测试补「重扫后无重复 path」断言|src/zmole/Features/Uninstall/UninstallViewModel.swift|
|t029_code_f010|minor|已修|删除零引用 `UninstallIdentity` 与 `UninstallApp.identity`|src/zmole/Features/Uninstall/UninstallSnapshot.swift|
|t029_test_f004|important|已修|用户 2026-10-17 在会话中明确批准 AC-005 文本变更（确认前只核对路径与 bundle id，卸载名变化由命令失败暴露），spec 保持已批准文本|docs/tasks/t029_uninstall_list_progressive/spec.md|

### Round 3 (2026-10-17T03:40:00+08:00)

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t029_code_f011|minor|已修|`performList` 结束（含取消路径）统一裁剪选中/关联/图标到本次流到的 path，隐藏选中不再残留|src/zmole/Features/Uninstall/UninstallViewModel.swift|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足（19/19 AC，见 `handoff.json` 的 `ac_evidence`；AC-005 文本经用户 2026-10-17 批准收紧为路径+bundle id）
- 测试：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` 236 通过（新增 PrewarmTests、UninstallStreamTests、UninstallTargetCheckerTests）；`pytest .repo_template/tests -q -m contract` 147 通过；`tests/integration/clean_trash_test.sh`、`installer_interface_test.sh`、`uninstall_stream_test.sh` 通过
- 黑盒：demo 卸载页（`--demo --demo-page uninstall --demo-state populated`，浅色 zh-Hans，新构建）显示同次扫描带来的版本/最近使用与大小；捆绑 `uninstall --list-stream` 实测身份行先行、完整行含 size/version/last_used_epoch、末 `{"event":"done"}`
- review：full 双轴 Round 4 PASS（code 4 轮、test 4 轮，全部 blocker 闭环）；`reviewed_scope 4cd8a9b2eaaa5528`；无未解决 finding
- AC 证据：见 `handoff.json`

### 结果摘要

- 卸载名单改为 `uninstall --list-stream` 渐进加载：先列身份、大小/版本/上次使用随后补上；图标异步补；预览/确认复用会话名单，确认前只做轻量身份核对（路径+bundle id），身份变化拒绝并重扫。
- 安装包删除不再重扫扫描根，只复核目标自身；页面会话复用名单。
- 新增空闲预跑队列（卸载名单→安装包名单→clean/optimize/purge dry-run）：单并发、无写入租约、写入开始取消、写入成功作废重跑、失败下次空闲重试；各页打开直接呈现预跑结果并标记扫描时间；demo 不预跑。
- 遗留：无
