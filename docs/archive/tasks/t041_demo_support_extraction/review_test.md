# Task review t041（reviewer_focus: 测试）

- task：`t041_demo_support_extraction`
- spec：`docs/tasks/t041_demo_support_extraction/spec.md`
- diff_anchor：`965d2b20c345bb1dd809fdc3d8e556cd42bf9527`
- target：`git -C '/Users/karson/kar/code/zmole_t041' diff 965d2b20c345bb1dd809fdc3d8e556cd42bf9527`
- round：1
- reviewed_at：2026-10-17T14:27:11+08:00

## Findings

### t041_test_f001 - AppAssemblyTests 对 AppDependencies 中的 Demo 类型守卫存在检测盲区（变异实证）

- 严重度：minor
- 锚点：AC-001 的回归守卫缺口——当前工作副本本身满足 AC-001（grep 证实无 Demo* 定义），但新增守卫测试漏检部分 `Demo*` 类型定义；不构成现行 AC 违反，故 non-blocking
- 位置：`tests/unit/AppAssemblyTests.swift:5-23`（负向断言在 `:7-22`）
- 问题：负向断言只匹配 4 个固定字符串：`final class DemoMoleProcess`、`struct Demo`、`enum DemoFixtures`、`"entries":[`。在临时副本做变异实证：追加 `private struct DemoGhost {}` 到 `AppDependencies.swift` → 测试失败（有效）；换成 `private enum DemoGhost {}` → 测试通过（漏检）。即非 DemoFixtures 的 `enum Demo*`（如 `enum DemoState`/`DemoAppearance`）、无 `final` 的 `class Demo*`、`extension Demo*` 均能溜过守卫，而它们都违反 AC-001「不再包含任何 Demo* 类型……demo 专用扩展」的意图。
- 建议：最小修复是负向 pattern 改前缀式集合（`struct Demo`、`class Demo`、`enum Demo`、`extension Demo`）并对 `"` fixture 字面量保留现有检查；若采纳，spec「测试策略」中的 pattern 描述同步更新。

### t041_test_f002 - AC-003 括号枚举的「CommandConcurrencyTests 的 demo 装配路径」与实际测试内容不符

- 严重度：minor
- 锚点：AC-003 描述性不符（操作要求「全量 `xcodebuild test` 通过」已满足并有测试；括号内的用例归属失准），处置方向为改 spec
- 位置：`tests/unit/CommandConcurrencyTests.swift`（全部 6 个用例：`testCommandBridgesAreDistinct`、`testAppDependenciesWiresDistinctLanes`、`testBusyReadLaneDoesNotBlockAnotherReadLane`、`testActiveStatusStreamDoesNotBlockReadLane`、`testTwoWriteViewModelsCannotRunConcurrently`、`testSameBridgeRejectsConcurrentRun`）
- 问题：该 suite 无任何 demo 路径——全仓 grep 证实测试中零处引用 demo（`MoleCommandLanes.demo` 仅被 `src/zmole/App/AppDependencies.swift:81` 调用，测试零引用 `.demo(`）；`git log -S demo -- tests/unit/CommandConcurrencyTests.swift` 无历史命中。AC-003 其余枚举（`ZmoleTests` 的 demo 配置/卸载预览/状态流 6 例、`PrewarmTests.testDemoConfigurationDisablesPrewarm`）均核实存在并通过。
- 建议：修正 spec AC-003 括号描述（改 spec，不改实现）；如确需 demo lanes 的并发语义覆盖，另起 follow-up 添加用例，本 task 不扩围。

## 结论

- 改测方向复核：无。本轮没有任何既有测试被修改或删除（`git diff --name-status` 无测试文件条目），新增 `AppAssemblyTests.swift` 为纯新增结构守卫；不存在「迁就实现」的改测。
- 本轮新发现：2 条（minor 2）。
- 危险模式扫描：逐项调查后无命中。新增测试的两个 `XCTAssertTrue(source.contains(...))` 存在性断言经调查不构成「以存在冒充行为」——AC-001 本身是源码结构 AC，spec「可测试性声明」已指定源码结构断言为其自动化方式，spec「测试策略」明确要求此测试；其余（恒真断言/删断言/`.skip`/静默错误/弱化断言/阈值掩盖/条件跳过）在 diff 中零命中。
- 未进表的提示：
  - 流程观察：两个新交付文件（`src/zmole/App/DemoSupport.swift`、`tests/unit/AppAssemblyTests.swift`）在 `git status --short` 中仍为 `??`，未执行派审要求的 `git add -N`，因此不在 `git diff 965d2b2` 可见范围。我通过文件系统全文读取（501/48 行），并在临时副本上完成构建/测试；独立重算 review 指纹得 `48a328dbc6c787b7`（含 untracked 交付文件），与派审值一致，无 reviewer 不可见内容，不判 INCOMPLETE。执行 commit 时需确保两文件入库。
  - AC-005 的「行数少于拆分前一半」无自动测试；属一次性搬迁目标，持久化行数断言无长期意义，reviewer 以 `wc -l` 复验（300 < 398），不建议为此补测试。
  - 可选硬化（不阻断）：`AppAssemblyTests.testDemoSupportFileCarriesTheDemoTypes` 为存在性断言，注释里写同名符号即可满足；可改为断言行首声明 pattern。当前有全量编译与行为用例兜底，风险低。
- 总体判断：纯搬迁逐字节等价（anchor 版 demo 块与新 `DemoSupport.swift` 正文仅差 3 处 spec 允许的 `private`→模块内可见调整 + 1 个尾部空行；行为零变化），5/5 AC 独立复验通过，2 条 minor 均为守卫/描述类问题，无未解决 critical / important。
- AC 复验方式：
  - AC-001 re_verified：对工作副本 `AppDependencies.swift` grep `Demo` 仅剩装配引用（`:61/:63/:82-84/:180-181`），无类型定义、fixture 字面量或 demo 扩展；旧 demo 块（anchor 版 `AppDependencies.swift:38-533`）与新 `DemoSupport.swift:7-501` 机械 diff 仅 3 处可见性修饰 + 1 空行差；`AppAssemblyTests` 两例实跑通过，并经变异验证断言可失败（见 f001）。
  - AC-002 re_verified：临时副本 `xcodegen generate` 退出码 0，且重生成 `project.pbxproj` 与被审版本 `diff` 退出码 0；`xcodebuild build -scheme Zmole -destination 'platform=macOS'` 退出码 0（BUILD SUCCEEDED）。
  - AC-003 re_verified：副本全量 `xcodebuild test` 退出码 0，`Executed 281 tests, with 0 failures`；逐名核对 demo 用例：`ZmoleTests` 6 例（配置 4 + 卸载预览 + 状态流）、`PrewarmTests.testDemoConfigurationDisablesPrewarm`、`CommandConcurrencyTests` 全 suite 均 passed。
  - AC-004 re_verified：`clean_trash_test.sh` / `installer_interface_test.sh` / `uninstall_stream_test.sh` 依次退出码 0（均打印 all cases passed）。
  - AC-005 re_verified：`wc -l` 得 `AppDependencies.swift` = 300 < 398（796/2），内容仅 `UnavailableMoleProcess` / `UnavailableMoleStreaming` / `MoleProcessBox` / `AppDependencies` / `ActivityCoalescer` 装配与装配辅助。
  - coverage = 5/5 re_verified（trust_prior 0）。
- 系统性 follow-up：无（f001/f002 均可在本 task adoption / finalization 内处置；未发现跨 task 测试基础设施、公共代码或工具链缺口）。

reviewed_scope: 48a328dbc6c787b7

verdict: PASS

## Round 2 (2026-10-17T14:37:05+08:00)

### 前轮 finding 复核

- t041_test_f001（minor）**修不彻底**：守卫已从固定字符串改为正则 `\b(class|struct|enum) Demo[A-Z]`（`tests/unit/AppAssemblyTests.swift:11-14`），判别力实测提升——临时副本向 `AppDependencies.swift` 追加 `private enum DemoGhost {}` 后 `xcodebuild test -only-testing:ZmoleTests/AppAssemblyTests` 退出码 65，于 `AppAssemblyTests.swift:11` 失败。但残余盲区仍在：追加 `extension DemoMoleProcess {}` 后同一用例通过（退出码 0），而 AC-001 明文禁止「demo 专用扩展」；正则要求 `Demo` 后紧跟 `[A-Z]`，裸 `struct Demo {}` 与 `actor DemoX {}` 亦不可检出（Round 1 旧版 `contains("struct Demo")` 可检出裸名，属边角回退）。当前工作副本 grep 证实无此类声明，不构成现行 AC 违反，维持 minor。
- t041_test_f002（minor）**已消除**：`git diff 965d2b2 -- spec.md` 显示 AC-003 括号内「`CommandConcurrencyTests` 的 demo 装配路径」已删，措辞与 `CommandConcurrencyTests.swift` 实际内容（无 demo 路径）一致。

### 本轮新发现

0 条。修复未引入新问题：新正则对当前 `AppDependencies.swift` 零命中（python/Swift 双重验证，无假阳），`enum DemoFixtures` 与 `"entries":[` 检查未动，`DemoSupport.swift` 存在性守卫未变。

- 改测方向复核：无「迁就实现」。本轮唯一测试文件变更为 `AppAssemblyTests.swift` 守卫增强（变异 A 证实可失败），无既有测试被修改 / 删除 / 弱化。
- 危险模式扫描：零命中（正则断言属 AC-001 结构断言的自动化方式，spec 测试策略明确要求；无恒真断言 / 删断言 / `.skip` / 静默错误 / 条件跳过 / 阈值掩盖）。
- AC 复验方式（Round 2）：
  - AC-001 re_verified：工作副本 grep 无 `Demo*` 类型定义、fixture 字面量、demo 扩展；变异 A/B 正反双侧实证。
  - AC-002 re_verified：临时副本 `xcodegen generate` 退出码 0，重生成 `project.pbxproj` shasum 与受审版本一致；`xcodebuild test` 构建通过。
  - AC-003 re_verified：临时副本全量 `xcodebuild test` 退出码 0，`Executed 281 tests, with 0 failures`（含 AppAssemblyTests 2 例）。
  - AC-004 re_verified：三条集成脚本依次退出码 0（均打印 all cases passed）。
  - AC-005 re_verified：`wc -l` = 300 < 398；文件仅含 `UnavailableMoleProcess` / `UnavailableMoleStreaming` / `MoleProcessBox` / `AppDependencies` / `ActivityCoalescer` 装配与装配辅助。
  - coverage = 5/5 re_verified（trust_prior 0）。
- 未进表提示（可选硬化，不阻断）：`AppAssemblyTests.swift:12` alternation 补 `extension`（如 `\b(class|struct|enum|extension|actor) Demo`）可消 f001 残余；`testDemoSupportFileCarriesTheDemoTypes` 仍为存在性断言（Round 1 已提示，未变）。
- 总体判断：f002 已消除；f001 判别力提升但残余 minor 盲区（`extension Demo*` / 裸 `Demo` 名，实测不触发现行 AC 违反）；无未解决 critical / important，Round 2 PASS。
- 系统性 follow-up：无。

reviewed_scope: 61e0de2cd0914f08

verdict: PASS
