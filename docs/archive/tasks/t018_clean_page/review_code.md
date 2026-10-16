# Task review t018（reviewer_focus: code）

- task: t018_clean_page（清理页整次预览后执行）
- spec: `docs/tasks/t018_clean_page/spec.md`
- diff_anchor: `ef1efac64fa4d2338b4ff5e421b26f4512d91fb0`
- target: `git -C /Users/karson/kar/code/zmole_t018 diff ef1efac`
- round: 1
- reviewed_at: 2026-10-16T19:02:00+08:00

门禁复核（本 worktree 实测）：

- `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 129 pass / 0 fail（`** TEST SUCCEEDED **`）。
- `pytest .repo_template/tests -q -m contract` → 147 passed。
- `bash tests/integration/clean_trash_test.sh` → all cases passed（8/8）。
- `project.yml` → `xcodegen generate` 产物与 `Zmole.xcodeproj/project.pbxproj` 逐字节一致（在临时目录重生成对比），新文件属生成结果，非手改。

## Findings

### t018_code_f001 - 清理 dry-run 与 status watch 共用同一 MoleStreaming，会互相取消/占忙

- 严重度: important
- 锚点: `src/zmole/App/AppDependencies.swift:349`、`src/zmole/App/AppDependencies.swift:370`、`src/zmole/Features/Clean/CleanViewModel.swift:143`
- 位置: `AppDependencies` 把同一个 `streaming`（非 demo 下为 `streamBridge`）同时注给 `StatusViewModel` 和 `CleanViewModel`（`streaming: configuration.isEnabled ? nil : streaming`）。`MoleBridge` 只允许一个 `activeRunner`（`MoleBridge.swift` `guard activeRunner == nil else ...busy`），且 status 的 `stopProcess()` 会 `await streaming.cancel()` 取消当前 runner。
- 问题:
    1. 离开 status 页进入 clean 时，`AppShellView.updateStatusWatch` 以 `Task { await statusViewModel.stop() }` 异步触发（`AppShellView.swift:108`），其 `stopProcess → streaming.cancel()` 会取消当前桥上的 runner；若此刻用户已点「再次扫描」，clean 的 dry-run 会被连带取消，页面落到「clean.cancelled」，用户看到一次无解释的取消。
    2. 反向场景更确定：clean dry-run 正在流式扫描（可能持续数秒到数十秒，`CleanView` 无 `onDisappear` 取消），用户切到概览/状态页 → `statusViewModel.start()` 在同一桥上 `stream(...)` 得到 `busy`，状态页直接进入错误态；clean 的 dry-run 变成无人观看的孤儿进程。
    - 代码内注释原本声明的意图是「one-shot 命令用第二个 bridge，避免与 watch 抢 busy」，本 task 让 clean 改走 watch 的 bridge，正好破坏该隔离。
- 建议: 给 clean 分配独立的 `MoleBridge` 实例（或复用 `commandBridge` 之外的第三个 stream bridge / 在 `MoleStreaming` 上做串行化），并补一条覆盖「status watch 活跃时 clean 预览仍可用」的回归测试。

### t018_code_f002 - 新增流式 dry-run 分支与 AC-002/AC-006 无自动测试，未兑现可测试性声明

- 严重度: important
- 锚点: `src/zmole/Features/Clean/CleanViewModel.swift:133`（`runDryRun` 流式分支）、`tests/unit/CleanPageTests.swift`
- 位置: spec「可测试性声明」写明「假 Bridge 输出阶段行与预览文件，自动断言 argv、预览世代、角标和文案」，并称 AC-001–007 均可自动测试。
- 问题:
    - 新增 `runDryRun` 的流式分支（`streaming != nil`，即生产路径）零覆盖。`CleanPageTests` 只直接单测 `CleanStageCatalog.stage(fromLine:)`，从未把假 `MoleStreaming` 注入 `CleanViewModel`，因此 AC-004 的「扫描输出出现 Browsers → 界面显示译名」只在解析层验证，未走 `streaming → currentStage → 视图` 的生产链路；该分支的错误/取消/非零退出处理（`commandFailed`、`.cancelled`）也无测试。
    - AC-002（取消确认后不执行、且该预览不可再次确认）与 AC-006（执行失败保留失败摘要）在 `CleanViewModel`/视图层均无断言。现有 `CleanPresentationTests` 只测 `OperationSession.cancelConfirmation()`，`CleanPreviewStoreTests` 只覆盖 verify 失败，未覆盖 `cancelConfirmation`/执行失败后的 `canConfirm`、`preview`、`errorMessageKey`/`executionSummary` 保留语义。
- 建议: 新增 `FakeMoleStreaming`（发 `➤ Browsers` 等阶段行 + 写预览文件），断言 `currentStage`、`lastReclaimBytes` 与非零退出的错误映射；补 `cancelConfirmation` 后不可再确认且未执行、`process.run(["clean"])` 非零后 `errorMessageKey`/`executionSummary` 仍在的两条用例。

### t018_code_f003 - 页面重写后遗留无用本地化键

- 严重度: minor
- 锚点: `src/zmole/Resources/Localizable.xcstrings`
- 位置: `mode.clean`、`clean.preview_title`、`clean.preview_scope`、`clean.preview_count`、`clean.preview_ready` 在 diff 后已无任何 Swift 引用（`rg` 全仓无命中；`CleanView` 改用 `sidebar.clean` 与分节/统计键）。
- 问题: 失效字符串仍保留，`xcstrings` 与代码不同步，后续易被误当作仍生效的文案。
- 建议: 删除上述键（属当前 task 重写引发的死数据，可安全清理）。

### t018_code_f004 - 阶段名单双份维护、流式 dry-run 无超时、entry id 可碰撞

- 严重度: minor
- 锚点: `src/zmole/Features/Clean/CleanScanStage.swift`（`sections` 数组与 `keys` 字典）、`src/zmole/Features/Clean/CleanViewModel.swift:143`、`src/zmole/Features/Clean/CleanPreviewModel.swift`（`CleanPreviewEntry.id`）
- 问题:
    1. `CleanStageCatalog.sections`（15 个名字）与 `keys` 字典的键完全重复，需双份同步维护，增删阶段名时易漂移；`sections` 仅作无箭头行的回退匹配，可直接由 `keys` 派生。
    2. 流式 dry-run 传 `timeout: nil`（一次性路径为 120s），无超时保护；卡死时只能靠用户手动取消。
    3. `CleanPreviewEntry.id = path + "\0" + rawLine`，同一 `rawLine` 重复出现时 id 碰撞，`ForEach` 会产生重复 id 警告/渲染异常（ledger 已去重，风险低）。
- 建议: 用 `keys.keys` 派生名单；流式 dry-run 复用与一次性路径一致的超时语义或显式说明无超时的理由；id 追加序号或改用 `Identifiable` 数组索引消歧。

## 结论

- 本轮新发现: 4 条（important ×2、minor ×2）。f001 为功能性设计回归，f002 为可测试性/TDD 缺口，二者未解决不得 PASS。
- 未进表的提示: 无。AC-001/003/004/005/007 的界面与文案实现（`--dry-run` argv、无子集执行控件、保护写入白名单且失效预览、侧边栏角标、zh-Hans 废纸篓文案）经代码走查与门禁实测均满足；`project.pbxproj` 与 `project.yml` 一致，无需整改。
- 总体判断: 主体实现方向正确（预览解析、阶段目录、角标、保护联动均落地并有部分测试），但 streaming 桥共享引入跨页干扰，且新增生产流式分支与两条 AC 未纳入自动测试，与 spec 的可测试性声明不符。
- 系统性 follow-up: 建议将「长驻 watch 与一次性命令不得共用同一 `MoleStreaming`」写入 blueprint/decisions，统一桥接资源的分配约定。

verdict: FAIL（Round 1）

### Round 2 (2026-10-16T19:25:00+08:00)

门禁复核（本 worktree 实测）：`xcodebuild test -scheme Zmole` → 133 pass / 0 fail（`** TEST SUCCEEDED **`）；`pytest .repo_template/tests -q -m contract` → 147 passed；`bash tests/integration/clean_trash_test.sh` → 8/8。自 Round 1 仅 `AppDependencies.swift`、`CleanScanStage.swift`、`CleanViewModel.swift`、`tests/unit/CleanPageTests.swift` 变化，其余文件未动。

#### 处置

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t018_code_f001|important|已修|新增第三个专用 `MoleBridge`（`cleanPreviewBridge`）供 clean dry-run 流；status watch 用 `streamBridge`、一次性命令用 `commandBridge`，三条流互不抢 active-runner，也不再互相 `cancel()`|`AppDependencies.swift:306,324-337,354`|
|t018_code_f002|important|已修|假 `MoleStreaming`（`CleanPageStreaming`）注入路径已覆盖：断言 argv、live `currentStage`、`lastReclaimBytes`、可确认，以及 `cancelPreview` 触发流取消|`CleanPageTests.swift:103,129`|
|t018_code_f003|minor|撤回|`mode.clean` / `clean.preview_*` 在 `diff_anchor` 之前即存在，非本 task 引入；清理属越界，留待后续 hygiene|—|
|t018_code_f004|minor|部分修|阶段名单已由单一 `keys` 派生（`sections = keys.keys.sorted()`），流式 dry-run 超时改为 300s；`CleanPreviewEntry.id` 碰撞项未改（ledger 已去重，风险极低），留作提示|`CleanScanStage.swift:30`、`CleanViewModel.swift:143`|

#### 新发现

### t018_code_f005 - AC-002/AC-006 仍无专用自动断言（覆盖缺口）

- 严重度: minor
- 锚点: `tests/unit/CleanPageTests.swift`、`tests/unit/CleanPresentationTests.swift:15`
- 位置: spec 可测试性声明称 AC-001–007 均可自动测试。
- 问题: AC-002（取消确认后不执行、且该预览不可再次确认）仅在 `OperationSession` 层测 `cancelConfirmation` 置空 preview，未在 `CleanViewModel` 断言「未发出 `["clean"]` 且 `canConfirm` 为假」；AC-006（执行失败保留失败摘要）无「`process.run(["clean"])` 非零后 `errorMessageKey`/`executionSummary` 仍在」的断言（`CleanPreviewStoreTests` 只覆盖 verify 失败）。
- 判定: 行为实现与既有逻辑一致、风险低，故列 minor；建议后续补两条用例封闭 AC 覆盖。
- 建议: 在 `CleanPageTests` 增加 `cancelConfirmation` 后 argv 不含 `["clean"]`、`canConfirm == false`；以及执行非零退出后失败摘要保留的断言。

#### Round 2 结论

- 处置确认: f001、f002 已修并实测；f004 主要项已修（名单单一来源、超时 300s），残留 `id` 碰撞为提示；f003 撤回（非本 task 引入）。
- 新发现: 1 条（minor，t018_code_f005）。无 critical/important 未解决。
- 回归扫描: 三座 `MoleBridge` 分流后无跨流取消/占忙路径；demo/不可用分支 `cleanStreaming = nil`，回落到一次性路径，与 Round 1 行为一致；新增静态检查测试（`testCleanViewHasNoSubsetExecutionControl`、`testStageLocalizationKeysHaveThreeLocales`）覆盖 AC-003 无子集控件与 AC-004 三语阶段键，未发现回归。
- 总体判断: Round 1 两项 important 均已闭环，剩余为 minor 覆盖/健壮性提示，可 PASS。

reviewed_scope: 8a70ed92bb4d7e6c

verdict: PASS
