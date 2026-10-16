# Task review t024（reviewer_focus: 通用）

- task: t024 历史页与设置页
- branch: `t024_history_settings`
- worktree: `/Users/karson/kar/code/zmole_t024`
- diff_anchor: `cb934138cb075b79802ed765e1cff753e8c1a3aa`（HEAD 即 anchor，改动为工作区变更）
- review_level: single；finding 前缀 `t024_gen_`
- 门禁复跑：
    - `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → **178 passed, 0 failures**（含本 task 新增 8）
    - `pytest .repo_template/tests -q -m contract` → **147 passed, 367 deselected**
- 范围：仅 diff 触及路径。未对 GUI 黑盒做额外要求。

## Findings

### t024_gen_f001 — minor — 历史刷新对 `history --json` 执行两次，展示行与导出 JSON 可能不同源

`HistoryViewModel.refresh()` 先调 `loader.loadRaw(limit:)` 拿导出用原文，再调 `loader.load(limit:)`；而 `HistorySnapshotLoader.load(limit:)` 内部又调用一次 `loadRaw(limit:)`（`HistoryViewModel.swift:87-89`、`:19-31`、`:34-43`）。后果：

- 每次刷新多 spawn 一次 mole 进程；历史非致命但无谓。
- `rawJSON`（导出源）与 `snapshot`（展示行）来自两次独立调用。若两次之间 history 发生变化，导出的"本次 JSON"与页面所示行不同源，与 AC-002「写出的文件内容与本次 history JSON 一致」的直觉存在偏差（现测试因 fixture 恒定而无法暴露）。

建议 `load` 复用同一份 raw 解码，refresh 只调一次。

### t024_gen_f002 — minor — `SMAppService` 的 `.requiresApproval` / `.notFound` 被当作"关闭"，成功注册也可能静默弹回

`SMAppServiceLoginItem.isEnabled()` 仅判 `status == .enabled`（`LoginItem.swift:44-46`），`LoginItemViewModel.setEnabled(true)` 在 `register()` 不抛错后即以 `isEnabled` 回读状态（`:53-64`）。当系统返回 `.requiresApproval`（未公证应用常见：已注册但待用户在系统设置批准）或 `.notFound` 时，`register()` 不抛错，开关却回读为关闭，且 `failureReason` 为 nil——用户把开关打开又立即弹回，无任何原因提示。这与 AC-004「注册成功时开关开启」及风险护栏（"不假装开启"之外，也不应无解释地假装失败）不完全一致。建议将非 `.enabled` 且非抛错的终态映射为可读原因。

### t024_gen_f003 — minor — 新增的白名单错误本地化键未接入生产 UI

`WhitelistViewModel` 为无效输入写入了本地化键（`whitelist.error.invalid_path` / `invalid_task_id` / `comment` / `duplicate`，`WhitelistViewModel.swift:73-90`），但 `WhitelistView` 仍直接渲染硬编码中文 `Text(errorMessage)`（`WhitelistView.swift:51-54`），未使用 `errorMessageKey`。对照 Optimize/Purge/Clean/Uninstall 视图均以 `UtilityNotice(title: LocalizedStringKey(errorMessageKey))` 呈现，本页在英文/繁中界面下会显示简体中文错误文本，且新增的 4 个 xcstrings 键在生产代码中成为死键（仅测试引用）。建议视图改用 `errorMessageKey`。

## 通用检查清单复核（仅列结论）

- spec 合规：8 条 AC 全部满足，见下「AC 复验方式」。
- 正确性：空状态/内容态由 `HistorySnapshot.displayState` 驱动（`HistorySnapshot.swift:14-22`）；optimize 任务 id 校验、注释行拒绝、重复拒绝顺序正确；两份白名单文件路径正确——`~/.config/mole/whitelist_optimize` 与捆绑 mole `lib/manage/whitelist.sh:22` 一致。
- 安全：导出仅写用户经 `NSSavePanel` 选择的路径，`atomically: true`；无硬编码密钥、无越权路径写入。
- 契约/类型：`LoginItemControlling` 协议 + 替身可测；`WhitelistKind`、`AppAppearance` 均为 `Sendable`；无 `try!`/强制解包；pbxproj 新增三个源文件与测试文件均入对应 target。
- 性能：除 f001 的双调用外无异常（本任务未引入新的常驻/轮询）。
- 架构：设置页复用共享 `purgePathsViewModel` 与 `PurgePathsEditorView`（与 t021 单一实现一致）；optimize/clean 共用 `WhitelistViewModel` 以 `kind` 区分；`AppDependencies` 统一装配，页面不新建生产 Bridge；符合 `docs/blueprint/architecture.md` 新段落。
- 健壮性：登录项失败保留编辑/开关与原因（f002 为边界态缺口）；保存成功后经共享 coordinator `invalidatePreviews()` 使清理预览失效（`WhitelistViewModel.swift:131`），与 clean 页同实例。
- 测试可信度：测试触达生产类型（`HistorySnapshotLoader`、真实 `WhitelistViewModel`/`WhitelistStore`、`BundledMoleInfo.parseTag`），非镜像实现；AC-005/AC-008 用源码结构断言（无 `MenuBarExtra(`、无禁用开关串），可接受。AC-003 仅断言枚举映射与 storageKey 字符串，未做真实跨启动/UserDefaults 往返——覆盖偏弱但符合 spec 可测性声明。AC-007 用合成文本测 `parseTag`，未对真实 bundle `SOURCE_VERSION` 断言。
- 文档一致性：`docs/blueprint/architecture.md`、`domain.md`、`docs/design/ui_contract.md` 三处更新与实现一致（外观持久化、登录项失败语义、`whitelist_optimize`、CLI 行、不常驻）。`Localizable.xcstrings` JSON 合法（401 键），新增键全部存在、无缺键。

## AC 复验方式

|AC|方式|依据|
|---|---|---|
|AC-001|re_verified|`displayState` + `HistoryView` 渲染；测试 `testEmptyHistoryShowsEmptyStateAndExportMatchesJSON`|
|AC-002|re_verified|`export(to:)` 原样写 `rawJSON`；测试断言文件内容 == 夹具 JSON|
|AC-003|re_verified|`@AppStorage` 键 + `AppShellView.preferredColorScheme/resolvedLocale` 读取；测试断言键与映射|
|AC-004|re_verified|`FakeLoginItem` 替身；测试断言失败保持关闭 + 原因、成功开启|
|AC-005|re_verified|`AppLifecycle` + `AppDelegate.applicationShouldTerminateAfterLastWindowClosed`；测试断言策略值与无 `MenuBarExtra`|
|AC-006|re_verified|`isValidTaskID`/注释/重复校验 + 共享 coordinator 失效；测试 `testOptimizeWhitelistAcceptsTaskIDsOnly`、`testCleanWhitelistSaveInvalidatesPreviewViaSharedCoordinator`|
|AC-007|re_verified|`BundledMoleInfo.tag()` 读 bundle 内 `SOURCE_VERSION`；`SOURCE_VERSION` 实际为 `upstream_tag=V1.55.0`，CopyFiles `dstSubfolderSpec=7`(Resources)；测试 `testBundledMoleTagParsing`；全码无系统 `mo` 探测|
|AC-008|re_verified|测试 `testSettingsHasNoRemovedToggles` 扫描 `SettingsView.swift`|

coverage = re_verified / 8 = **8 / 8**

## 结论

3 个 minor finding，无 critical/important；8 条 AC 全部 re_verified，门禁双绿（178 + 147）。

verdict: PASS

### Round 2 (2026-10-16T20:46:09+08:00)

对 `git -C /Users/karson/kar/code/zmole_t024 diff cb934138cb075b79802ed765e1cff753e8c1a3aa` 复核；相对 Round 1 仅 `HistoryViewModel.swift`、`LoginItem.swift`、`WhitelistView.swift` 与 `Localizable.xcstrings`（新增 `settings.login_item.pending`）变化。

|finding_id|severity|status|复核结论|
|---|---|---|---|
|t024_gen_f001|minor|已修|`refresh()` 单次 `loadRaw()` 后经 `HistorySnapshotLoader.decode(_:)` 解析同一 raw，`rawJSON` 仅在解码成功后赋值（`HistoryViewModel.swift:88-92`）；`load(limit:)` 改为 `loadRaw`+`decode`；Overview 的 `load(limit:)` 仍单次调用。展示行与导出 JSON 现同源。|
|t024_gen_f002|minor|已修|`setEnabled(true)` 在 `register()` 返回后回读 `isEnabled()`；非 enabled 且未抛错时置 `isEnabled=false` 并 `failureReason=String(localized:"settings.login_item.pending")`（`LoginItem.swift:56-70`）。键存在且英/简中/繁中齐全（`Localizable.xcstrings:405`），不再静默弹回。|
|t024_gen_f003|minor|已修|`WhitelistView` 优先渲染 `LocalizedStringKey(viewModel.errorMessageKey)`，无键时回退 `errorMessage`（`WhitelistView.swift:50-57`）。新增 4 个白名单错误键接入生产 UI。|

回归扫描：**无新增 finding**。

- `HistorySnapshotLoader.load` 对外签名/语义未变，`OverviewViewModel.swift:94` 调用正常。
- `WhitelistViewModel`/`WhitelistView` 其余改动（kind 标题、占位符、摘要）与 Round 1 相同，未引入新行为。
- `setEnabled(false)` 分支未改；`FakeLoginItem.register()` 置 enabled=true，既有成功用例不受影响。
- `Localizable.xcstrings` JSON 合法，新增 1 键、无缺键；`settings.login_item.pending` 文案为「在系统设置批准」，对 `.notFound` 场景措辞略偏（观察项，非 finding，因已消除静默、且无 AC 覆盖）。

门禁复跑：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` → **178 passed / 0 failures**；`pytest .repo_template/tests -q -m contract` → **147 passed, 367 deselected**。

AC 复验方式：Round 1 的 8 条仍全部 `re_verified`，本轮改动未触及 AC 面；coverage = re_verified / 8 = **8 / 8**。

结论：Round 1 三个 minor 全部已修，无新 finding，无回归。

reviewed_scope: ca198a9fd7f794ab

verdict: PASS
