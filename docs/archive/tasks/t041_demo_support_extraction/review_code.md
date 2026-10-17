# Task review t041（reviewer_focus: 代码）

- task：`t041_demo_support_extraction`
- spec：`docs/tasks/t041_demo_support_extraction/spec.md`
- diff_anchor：`965d2b20c345bb1dd809fdc3d8e556cd42bf9527`
- target：`git -C '/Users/karson/kar/code/zmole_t041' diff 965d2b20c345bb1dd809fdc3d8e556cd42bf9527`
- round：1
- reviewed_at：2026-10-17T14:17:47+08:00

## Findings

### t041_code_f001 - `private` 跨文件调整已执行但未按要求给出说明

- 严重度：minor
- 锚点：spec 范围第 3 条「如有 `private` 跨文件移动需求，改为文件级 `fileprivate`→模块内可见的等价调整并说明」——调整已完成，说明缺失；无对应 AC，无行为缺陷，按文档性缺口计 minor
- 位置：`src/zmole/App/DemoSupport.swift:19`（`final class DemoMoleProcess`）、`:209`（`struct DemoMoleStreaming`）、`:244`（`struct DemoUninstallListStream`）；原 `AppDependencies.swift:50`、`:240`、`:275` 的 `private` 被去掉
- 问题：三个被 `AppDependencies.init` 跨文件引用的类型由文件内 `private`（fileprivate 语义）放宽为模块内可见，这是搬迁的必要调整；但整个 diff 中找不到任何对此可见性调整的说明——`task.md` 实施笔记为「无」，`DemoSupport.swift` 头注释只说明文件边界，`docs/blueprint/architecture.md` 的更新只描述文件组织。spec 明确要求「并说明」，未来读者无法从交付物判断放宽可见性是有意为之还是遗漏。
- 建议：在 `task.md` 实施笔记（或 `DemoSupport.swift` 头注释）补一句，例如「DemoMoleProcess / DemoMoleStreaming / DemoUninstallListStream 由文件内 private 调整为模块内可见，供 AppDependencies 装配引用」。

## 结论

- 本轮新发现：1 条（minor 1）。
- 未进表的提示：
  - 文件过大：`src/zmole/App/DemoSupport.swift` 新建 501 物理行，达实现源码 minor 阈值（400）。按规范排除大块 fixture 正文后低于阈值：fixture 字面量段（`:116-187`，约 72 行）与 `DemoDiskScanner` 数据表（`:430-500`，约 71 行）为数据正文，扣除后约 358 行；且 spec 本身将该文件定为 demo fixture 容器并允许再分 `DemoFixtures.swift`。不进 finding 表。`AppDependencies.swift` 796 → 300 行，其余 diff 文件低于阈值。
  - 圈复杂度：`DemoMoleProcess.run`（`DemoSupport.swift:28-94`）手算近似 14–19，给 demo 命令源做 switch 分发；本 task 为逐字节搬迁（机械比对仅 3 处可见性修饰 + 1 个空行差异），未新增任何分支或嵌套，不构成符合 finding 条件的增量。不进 finding 表。
  - 流程观察：`Zmole.xcodeproj/project.pbxproj` 已按 xcodegen 同步（重生成结果与被审版本逐字节一致）；两个新交付文件（`DemoSupport.swift`、`AppAssemblyTests.swift`）在 git 状态中为 untracked（未 `git add -N`），但 `reviewed_scope` 指纹按完整 worktree（含 untracked 交付文件）计算并通过文件系统完整读取二者，无 reviewer 不可见的交付内容，不判 INCOMPLETE。
- 总体判断：纯净搬迁，行为零变化由逐字节机械比对证实；AC-001–AC-005 全部独立复验通过，唯一 finding 为 spec 要求的调整说明缺失（minor），无未解决 critical / important → PASS。
- AC 复验方式：
  - AC-001 re_verified：`AppDependencies.swift`（300 行）grep 仅剩装配引用（`:61/:63/:82-84/:180-181`），无任何 `Demo*` 类型定义、JSON fixture 字面量或多行字符串；将 anchor 版 `AppDependencies.swift:38-532` 的 demo 块与新 `DemoSupport.swift` 正文做机械 diff，差异仅为 3 处 `private` 修饰去除 + 1 个前导空行。配套结构测试 `AppAssemblyTests` 两例通过。
  - AC-002 re_verified：在 worktree 逐字节内容副本（`/var/folders/.../T/opencode/t041_verify`，避免在被审副本内落地 xcodegen 写文件）执行 `xcodegen generate`，生成的 `project.pbxproj` 与被审版本 `diff` 退出码 0；随后 `xcodebuild build -scheme Zmole -destination 'platform=macOS'` 退出码 0。
  - AC-003 re_verified：同一副本全量 `xcodebuild test -scheme Zmole -destination 'platform=macOS'` 退出码 0，「Executed 281 tests, with 0 failures」；日志确认 demo 用例全绿：`ZmoleTests.testDemoConfigurationSelectsPageLanguageAndAppearance` / `testDemoConfigurationRejectsDataRootOutsideTemporaryDirectory` / `testDemoLanguageFlagsRequireDemoGate` / `testDemoDependenciesInjectCleanAndWhitelistPathsWithoutMoleConfig` / `testDemoUninstallPreviewContainsOnlySelectedApplications` / `testPopulatedDemoStatusKeepsSamplingUntilPaused`、`PrewarmTests.testDemoConfigurationDisablesPrewarm`、`CommandConcurrencyTests` 全 suite。
  - AC-004 re_verified：副本内依次跑 `tests/integration/clean_trash_test.sh`、`installer_interface_test.sh`、`uninstall_stream_test.sh`，退出码均 0（all cases passed）。
  - AC-005 re_verified：`wc -l` 得 `AppDependencies.swift` = 300 < 398（796/2），内容仅 `UnavailableMoleProcess` / `UnavailableMoleStreaming` / `MoleProcessBox` / `AppDependencies` / `ActivityCoalescer`，与 anchor 版首 36 行、尾 534-796 行逐字节一致。
  - coverage = 5/5 re_verified（trust_prior 0）。
- 系统性 follow-up：无（未发现跨 task 的基础设施/公共代码/工具链缺口）。

reviewed_scope: 48a328dbc6c787b7

verdict: PASS

## Round 2 (2026-10-17T14:30:37+08:00)

- 复核范围：当前 worktree 相对 `965d2b20c345bb1dd809fdc3d8e556cd42bf9527` 的完整交付内容（含 untracked 的 `DemoSupport.swift` / `AppAssemblyTests.swift`）。与前轮相比的变化仅为 test 路修复及其文档：`tests/unit/AppAssemblyTests.swift` 守卫改为正则、`spec.md` AC-003 删除不存在的 `CommandConcurrencyTests` demo 路径、`task.md` 实施笔记与处置表。实现源码 `AppDependencies.swift`（300 行）/`DemoSupport.swift`（501 行）与 Round 1 一致：anchor demo 块机械 diff 仍仅 import/头注释、3 处 `private` 去除、1 个空行差异。

### 前轮 finding 复核

- t041_code_f001：已消除。`task.md:28` 新增「可见性调整说明（spec 要求）」，点名 `DemoMoleProcess` / `DemoMoleStreaming` / `DemoUninstallListStream` 三个类型原为 `private`、跨文件后改为模块内可见，并说明其余 demo 类型可见性不变、无对外 API 变化，满足 spec 范围第 3 条「并说明」。改动仅为文档，未引入新问题。

### 本轮新发现

0 条。

### 未进表的提示

无。

### AC 复验方式

- AC-001 re_verified：`AppDependencies.swift` 300 行，正则 `\b(class|struct|enum) Demo[A-Z]` 零命中；anchor demo 块与 `DemoSupport.swift` 机械 diff 仍仅 header/import、3 处可见性修饰、1 空行。
- AC-002 re_verified：当前 worktree 副本内 `xcodegen generate` 成功，`xcodebuild test`（含 build）`** TEST SUCCEEDED **`。
- AC-003 re_verified：同一副本全量 `xcodebuild test -scheme Zmole -destination 'platform=macOS'` 通过，`Executed 281 tests, with 0 failures`；`tests/unit/CommandConcurrencyTests.swift` grep `Demo` 无命中，spec 删除该项属实。
- AC-004 re_verified：副本内重跑 `clean_trash_test.sh` / `installer_interface_test.sh` / `uninstall_stream_test.sh`，退出码均 0（all cases passed）。
- AC-005 re_verified：`wc -l src/zmole/App/AppDependencies.swift` = 300 < 398；内容仍仅装配与装配辅助。

coverage = 5/5 re_verified（trust_prior 0）。

- 总体判断：前轮唯一 minor 已按要求消除，修复未引入新问题；当前无未解决 critical / important。
- 系统性 follow-up：无。

reviewed_scope: 61e0de2cd0914f08

verdict: PASS
