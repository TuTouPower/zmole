# Task review t042（reviewer_focus: 代码）

- task：`t042_preview_lease_coordinator`
- spec：`docs/tasks/t042_preview_lease_coordinator/spec.md`
- diff_anchor：`166a65b5f4492efb2506f901fd66c87f2044aaed`
- target：`git -C '/Users/karson/kar/code/zmole_t042' diff 166a65b5f4492efb2506f901fd66c87f2044aaed`
- round：1
- reviewed_at：2026-10-17T14:55:12+08:00

审查范围补充：新交付文件 `src/zmole/Features/Operations/PreviewLeaseCoordinator.swift` 在 worktree 中为 untracked（未 `git add -N`），不在上述 `git diff` 输出内；已按 `git status --short` 发现并全文读取审查，构建与全量测试亦覆盖该文件（含编译）。指纹按含 untracked 交付文件的完整 worktree 计算，与本报告末行一致。

## Findings

本轮 0 finding。

规格合规逐项核查：AC-001–AC-004 均有实现且修复面收敛于 spec 范围（三个写路径 VM + 共享组件 + 结构测试 + 装配/文档同步），无范围外改动、无顺手改进、不变量（行为零变化）经逐路径比对成立。代码质量各视角（DRY / 控制流 / 错误处理 / 边界 / 命名 / 职责分离 / 死代码 / 安全 / 契约·Breaking / 性能 / 架构可维护 / 健壮性可观测 / 文档一致性）扫描后无可报项，不为凑数出 finding。

## 结论

- 本轮新发现：0 条。
- 未进表的提示：
  - 文件过大：`src/zmole/Features/Uninstall/UninstallViewModel.swift` 583 → 553 行（净减 30），仍在实现源码 400 行提示线之上，但按「已达阈值且本 task 净增」规则不构成 finding；`CleanViewModel.swift` 306、`MaintenanceOperation.swift` 262、新文件 `PreviewLeaseCoordinator.swift` 85、`CommandConcurrencyTests.swift` 198 均低于阈值。`Zmole.xcodeproj/project.pbxproj` 为 xcodegen 生成物（临时副本重生成与被审版本逐字节一致），排除计量。
  - 圈复杂度：新组件各方法 1–2；三个 VM 内最大函数（`confirmExecution` 等约 8–10）本 task 未新增分支或嵌套，仅替换调用点，均 <15。不进 finding 表。
  - 范围外观察：`PrewarmService.swift:94` 与 `OverviewViewModel.swift:313` 也各自订阅 `coordinator.$invalidationGeneration`，用途不同（预暖失效重排 / 概览缓存），不在本 spec 声明的三个写路径 VM 范围内，本 task 不做处理。
  - 流程观察：untracked 新交付文件（见上）内容已完整进入审查与指纹覆盖，不判 INCOMPLETE；提交时随实现 commit 入库即可。
- 总体判断：机械迁移对照 anchor 版本逐路径比对（获取/释放、捕获/清除世代、失效回调合取条件与清除时机、自身 invalidate 的同步重捕获次序）均为等价替换，行为零变化成立；无未解决 critical / important → PASS。
- AC 复验方式：
  - AC-001 re_verified：`git grep` 三文件无 `previewCoordinatorGeneration` / `private var lease` / `releaseLease` / 私有 `isCurrentPreview` / `operationID(for:`；三者均 `leaseCoordinator = PreviewLeaseCoordinator(coordinator:)`；共享组件位于 spec 建议路径且含 `PreviewOperationID.from`（ready/confirming/executing 三态）；结构测试 `CommandConcurrencyTests.testWriteViewModelsShareThePreviewLeaseCoordinator` 在全量运行中通过。
  - AC-002 re_verified：`xcodebuild test -scheme Zmole -destination 'platform=macOS'` → `Test Suite 'ZmoleTests.xctest' passed`、`Executed 282 tests, with 0 failures`、`** TEST SUCCEEDED **`；10 个指定 suite（CommandConcurrency/RecoverableBusy/CleanPage/CleanPreviewStore/Uninstall/UninstallDetail/BatchUninstall/Optimize/Purge/OptimizePurgePage）在日志中逐个 `passed`。
  - AC-003 re_verified：既有用例 `CleanPageTests.testProtectingPathInvalidatesCurrentPreview`、`OptimizePurgePageTests.testSavingScanDirectoriesInvalidatesPurgePreview` 通过；另将三个 VM 的失效回调与 anchor 版本逐行做合取条件与顺序比对（含 `.executing` 时 `expirePreview` no-op 但仍清世代、无预览时不消费世代、自身 `invalidatePreviews` 触发同步回调后重捕获），语义一致。事实备注：uninstall 的「外部失效 → 预览过期」无直接既有专测（spec 标注为既有用例覆盖），本项结论由代码等价比对支撑；测试覆盖判定属 test reviewer 职责。
  - AC-004 re_verified：全量 xcodebuild test 通过（同上）；`tests/integration/` 三脚本重跑退出码均 0——`clean_trash_test.sh`（8/8）、`installer_interface_test.sh`（15/15）、`uninstall_stream_test.sh`（7/7）。`docs/blueprint/architecture.md` 的更新与共享组件职责描述一致。
  - coverage = 4/4 re_verified（trust_prior 0）。
- 系统性 follow-up：无。

reviewed_scope: 85d4d588605b1e85

verdict: PASS

## Round 2 (2026-10-17T15:53:40+08:00)

本轮 delta（相对 Round 1）：`tests/unit/CommandConcurrencyTests.swift`（结构测试补负断言）、`tests/unit/UninstallDetailTests.swift`（新增 `testAnotherWriteInvalidatesAnUninstallPreview`，`makeViewModel` 支持注入 coordinator）、新交付文件 `PreviewLeaseCoordinator.swift` 经 `git add -N` 进入 `git diff`、`task.md` 处置表。生产代码自 Round 1 前未再改动（`src/` 文件 mtime 14:39–14:43 早于 R1 审阅 14:55；`git diff 166a65b -- src/` 仅含本 task 的 4 个文件 + 1 个新文件，其余与 HEAD 逐字节一致）。

### 前轮 finding 复核

- code 轴 Round 1：0 finding，无待复核 blocker。
- test 轴 R1 3 minor（判定属 test reviewer，本轴仅核对其对交付的影响，逐条以 diff/代码为准）：f001 结构负断言已落地——`tests/unit/CommandConcurrencyTests.swift:118-137` 含 `releaseLease(clearPreviewGeneration` / `previewCoordinatorGeneration` / `coordinator.$invalidationGeneration.sink` / `private var isCurrentPreview` / `private func operationID(for` 五个负断言，`rg` 复核三 VM 文件确无对应字符串，断言非恒真亦不误伤。f002 已落地——新用例走真实 `OperationCoordinator` + `PreviewLeaseCoordinator` + `UninstallViewModel`（spy 仅 stub 进程桥，未 mock 被测逻辑），移除组件订阅或失效回调即失败，且实跑通过。f003 已落地——`git status --short` 显示 `A  src/zmole/Features/Operations/PreviewLeaseCoordinator.swift`，该文件已进入本轮 `git diff` 与指纹。

### 本轮新发现：0 条

扫描结论：结构测试断言与源码实况一致、路径解析正确（tests/unit 上溯三级 = 仓库根）、负断言无假阳性；新用例语义成立（预览成功后 `canConfirm` 为真，外部 invalidate 递增共享 generation → 预览过期/`canConfirm` 为假，同步回调无需等待）；`makeViewModel` 增参向后兼容（既有调用点均标签传参且声明顺序不变）；测试目标整体编译通过。

### 未进表的提示

- 环境观察（非 delta 问题）：本轮复跑集成脚本时 `installer_interface_test.sh`、`uninstall_stream_test.sh` 在本机卡住（bash 阻塞等待 `uninstall.sh --list-stream` 子 shell；两次分别到 AC-003 / AC-004 后挂起）。`src/` 与脚本自 R1 前字节未变，`clean_trash_test.sh` 复跑 exit 0（8/8），判定为共享环境级 flake，与 t042 delta 无关，记录备查。
- 文件过大 / 圈复杂度：沿用 Round 1 结论，本轮无净增，不变。

## AC 复验方式（Round 2）

- AC-001 re_verified：结构测试（含新增负断言）实跑通过；`rg` 复核三 VM 无样板残留、`PreviewLeaseCoordinator(` 均在。
- AC-002 re_verified：当前 worktree 全量 `xcodebuild test` → `Executed 283 tests, with 0 failures`、`** TEST SUCCEEDED **`；两受影响类单独复跑 21/21 通过。
- AC-003 re_verified：`testAnotherWriteInvalidatesAnUninstallPreview` 实跑通过（外部 invalidate → 预览过期）；clean/optimize 既有失效用例在全量运行中通过。
- AC-004 re_verified（部分）：全量测试同上；`clean_trash_test.sh` 本轮 exit 0；`installer_interface_test.sh` / `uninstall_stream_test.sh` 本轮因上述环境卡住未复跑 → trust_prior（依赖 R1 已记录 15/15、7/7；delta 未触及其依赖路径，src 字节未变）。
- coverage = 4/4（其中 AC-004 的 2/3 集成脚本为 trust_prior，占比 <30%）。

## 结论（Round 2）

- 本轮新发现：0 条。
- 前轮 blocker 复核：无（R1 code 轴 0 finding）。
- 总体判断：R2 delta 仅测试改动与文件暂存，未引入新问题；新增/修改测试均为有效非恒真验证并实跑通过 → PASS。
- 系统性 follow-up：无（集成脚本 flake 为环境级观察，未见既有 pending 对应项）。

reviewed_scope: d9603947f8282d74

verdict: PASS
