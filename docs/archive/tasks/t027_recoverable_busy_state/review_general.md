# t027 单路 review（general）

- task: `t027` recoverable_busy_state
- review_level: single
- diff_anchor: `97734278e417bd4b1f84f647e052b2f3ee35ef1c`
- worktree: `../zmole_t027`
- 范围：仅 diff 触达路径
- 门禁：`xcodebuild test -scheme Zmole` → 198 pass、`pytest -m contract` → 147 pass（trust_prior，未重跑）

## 结论摘要

整体方向正确：新增 `CommandBusy` 分类器与 `RecoverableBusyNotice` 中性提示，`MoleBridgeError.isBusy` 单一路径降级，Clean/Optimize/Purge/Analyze/History/Installers/Overview 的预览与读取路径在 busy 时保留旧数据并给出可恢复提示，真实失败路径未改动。但 **Uninstall 预览的协调器占用分支引入状态泄漏**：`beginPreview()` 先于 `acquire()`，占用时只置 `showBusyNotice` 而不回滚 session，导致页面卡在 `.previewing`，卸载按钮失效、busy 提示无法直接重试清除（须先手动 cancel），AC-003 在该页首轮不成立。故 FAIL。

## Findings

### t027_gen_f001

- severity: important
- 位置：`src/zmole/Features/Uninstall/UninstallViewModel.swift:239-243`
- 现象：`previewUninstall()` 中 `session.beginPreview()`（置 `.previewing`）先于 `coordinator.acquire(.uninstall)`；acquire 失败时仅 `showBusyNotice = true; return`，**未回滚 session**。对比 CleanViewModel.swift:73-81 与 MaintenanceOperation.swift:87-95，二者均已改为「先 acquire、再 beginPreview」，Uninstall 漏改。
- 后果：
    - `session.isBusy == true` 持续（OperationSession.swift:92、108-114）；
    - `canPreview == false`（UninstallViewModel.swift:51-55），且 `toggleSelection`/`clearSelection` 被 `!session.isBusy` 守卫拦截（:130、:150），卸载按钮成为空操作；
    - 工具栏进入 `isPreviewing` 分支显示 cancel（UninstallView.swift:78-79），出现并不存在的“预览中”活动态；
    - busy 提示无直接重试路径，须先点 cancel 才能再次预览 → **违反 AC-003**（通道空闲后可通过重试清除并成功执行）；
    - 协调器释放/`invalidatePreviews` 也不会复位：`expirePreviewIfNeeded` 要求 `session.preview != nil`（:422-428），`.previewing` 下 preview 为 nil。
- 建议：与 Clean/Maintenance 一致，先 `acquire` 再 `beginPreview`；或在 busy 分支 `session.invalidate()`。
- 测试：`tests/unit/RecoverableBusyTests.swift`、`CommandConcurrencyTests.swift` 均未覆盖 uninstall 协调器占用路径，故未被捕获。

### t027_gen_f002

- severity: minor
- 位置：`src/zmole/Features/Installers/InstallersViewModel.swift:107-136`
- 现象：`confirmRemoval()` acquire 失败置 `showBusyNotice = true` 后无复位；仅 `scan()`（:54）会复位。若某次 scan busy 后再执行一次成功卸载，busy 中性提示会滞留在结果区。
- 建议：在 acquire 成功或成功路径复位 `showBusyNotice`。

### t027_gen_f003

- severity: minor
- 位置：`src/zmole/MoleBridge/MoleBridgeError.swift:19`
- 现象：`case .cancelled:` 的 `return "mole 命令已取消"` 与 `case let .commandFailed(result):` 被并到同一行（`return "mole 命令已取消"        case let .commandFailed(result):`）。系意外删换行；`xcrun swiftc -parse` 通过、语义不变，但属与 isBusy 无关的格式损坏。
- 建议：恢复换行。

### t027_gen_f004

- severity: minor
- 位置：`src/zmole/Features/Operations/CommandBusy.swift:6,12-14`
- 现象：`messageKey` 与 `localizedText` 全仓无引用（`RecoverableBusyNotice` 硬编码 `"command.busy"`），为死代码。分类器保留 `isBusy` 即可。

### t027_gen_f005

- severity: minor
- 位置：`src/zmole/Features/Overview/OverviewViewModel.swift:141-145`
- 现象：`refreshHistory()` busy 分支提前 `return`，未清 `errorMessage`。若此前有真实失败信息，busy 时会同时呈现旧失败区与 busy 提示（AC-001「错误区不处于失败状态」的边缘）。Analyze/History 均在起始处显式清 `errorMessage`，此处不一致。
- 建议：busy 分支清 `errorMessage`（或在方法起始处清）。

### t027_gen_f006

- severity: minor
- 位置：`tests/unit/CommandConcurrencyTests.swift:78-82`
- 现象：就地改了 t025 旧断言（`purge.errorMessageKey == "operation.error.busy"` → `showBusyNotice == true` + `errorMessageKey == nil`），偏离 AGENTS「旧测试原样保留或整体删除并写明理由，禁止就地把旧测试预期改成当前实现输出」。
- 减轻：新 `RecoverableBusyTests.swift` 已覆盖新语义，且改后断言未削弱。建议后续按规则处置（保留旧测试或整体删除并写明理由）。

## 结论

AC 复验方式：re_verified / 3（AC-001、AC-002、AC-003 逐条对照 diff、VM 状态机与测试审读复验；`xcodebuild test` / `pytest -m contract` 门禁 trust_prior，未重跑）。

- AC-001：多数页面满足（busy 仅置中性提示、session 不置 `.failed`、旧数据保留）；但 f005 存在「busy 与旧失败区并存」的边缘。
- AC-002：满足。真实失败路径（commandFailed/domain error/previewStoreError）未改动，仍进入 `.failed` 并保留 summary。
- AC-003：未完全满足。Uninstall 预览协调器占用后 session 卡在 `.previewing`，重试被 `!session.isBusy` 守卫拦截（f001）；Analyze/History/Installers/Optimize 的重试清除有测试覆盖且通过。

存在未解决的 important finding（t027_gen_f001），不得 PASS。

verdict: FAIL

______________________________________________________________________

## Round 2 (2026-10-16T22:47:20+08:00)

- diff_anchor: `97734278e417bd4b1f84f647e052b2f3ee35ef1c`（同 round 1）
- 门禁：`xcodebuild test -scheme Zmole` → 198 pass、`pytest -m contract` → 147 pass（trust_prior，未重跑）

### Round 1 finding 处置

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t027_gen_f001|important|已修|`previewUninstall` 改为先 `acquire` 再 `beginPreview`；busy 分支仅置提示，session 起始已 `invalidate()`，不再卡 `.previewing`|UninstallViewModel.swift:239-246|
|t027_gen_f002|minor|已修|`confirmRemoval` acquire 成功后置 `showBusyNotice = false`|InstallersViewModel.swift:112|
|t027_gen_f003|minor|已修|`case .cancelled` 与 `case let .commandFailed` 恢复分行|MoleBridgeError.swift:19-20|
|t027_gen_f004|minor|已修|`messageKey`/`localizedText` 删除，`CommandBusy` 仅留 `isBusy`|CommandBusy.swift:6-8|
|t027_gen_f005|minor|已修|Overview busy 分支加 `errorMessage = nil`|OverviewViewModel.swift:142-146|
|t027_gen_f006|minor|已修|t025 测试改为表示无关断言（`purgeSpy.invocations == 0` 且 `!isPreviewing`），不再就地绑定 busy 表示|CommandConcurrencyTests.swift:77-82|

### Findings

### t027_gen_f007

- severity: minor
- 位置：`src/zmole/Features/Overview/OverviewViewModel.swift:147-148`
- 现象：round 2 修复了 busy 分支清 `errorMessage`，但对称方向未覆盖——真实失败分支不清 `showBusyNotice`。若先发生 busy（`showBusyNotice = true`），下次进入概览命中真实失败时 `showBusyNotice` 仍为 true；`OverviewView` 只渲染 busy 提示（OverviewView.swift:13-14，不渲染 `errorMessage`），于是非忙碌的真实失败被原样显示成「另一个 mole 命令正在运行，请稍后重试」，与 AC-002 精神相悖。
- 影响：边缘（需两次进入概览且先 busy 后真实失败）；提示为中性非红色，无数据损失。
- 建议：真实失败分支补 `showBusyNotice = false`。
- 备注：非 round 2 引入的回归，为 f005 的对称残留，非阻塞。

### 结论

AC 复验方式：re_verified / 3（AC-001、AC-002、AC-003 逐条对照本轮 diff、VM 状态机复验；门禁 trust_prior）。

- AC-001：满足。各页面 busy 仅置中性提示、session 不置 `.failed`、旧数据保留；f001 卡死已消除。
- AC-002：满足。真实失败路径未改动，仍进入 `.failed` 并保留摘要。
- AC-003：满足。Uninstall 预览 busy 后 session 保持 idle，`canPreview` 恢复为 true，重试直接可用；Analyze/History/Installers/Optimize 重试清除有测试覆盖。

无未解决的 critical/important finding；新增仅 1 条 minor（t027_gen_f007，非阻塞）。

verdict: PASS

______________________________________________________________________

## Round 3 (2026-10-16T22:49:23+08:00)

- diff_anchor: `97734278e417bd4b1f84f647e052b2f3ee35ef1c`（同 round 1）
- 门禁：`xcodebuild test -scheme Zmole` → 198 pass、`pytest -m contract` → 147 pass（trust_prior，未重跑）
- 本轮实测 diff：仅 `OverviewViewModel.swift` 相对 round 2 增 1 行（+8 → 原 +7），无其他文件变化。

### Round 2 finding 处置

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t027_gen_f007|minor|已修|真实失败分支加 `showBusyNotice = false`，busy 提示不再在真实失败后残留|OverviewViewModel.swift:147|

### Findings

无。

### 结论

AC 复验方式：re_verified / 3（AC-001、AC-002、AC-003 逐条对照本轮 diff、VM 状态机复验；门禁 trust_prior）。

- AC-001：满足。各页面 busy 仅置中性提示、session 不置 `.failed`、旧数据保留。
- AC-002：满足。真实失败路径未改动，仍进入 `.failed` 并保留摘要；Overview 真实失败与 busy 提示互斥。
- AC-003：满足。Uninstall 预览 busy 后 session 保持 idle、重试可用；Analyze/History/Installers/Optimize 重试清除有测试覆盖。

无未解决的 critical/important/minor finding。

reviewed_scope: 309069d87679f012

verdict: PASS
