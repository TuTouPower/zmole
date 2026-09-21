# Task review t009（reviewer_focus: 代码）

- task：`t009_uninstall_run`
- spec：`docs/tasks/t009_uninstall_run/spec.md`
- diff_anchor：`c5264241db883bfce53fbb461ae0c276cde9f337`
- target：`git -C '/Users/karson/kar/code/zmole_t009' diff c5264241db883bfce53fbb461ae0c276cde9f337`
- round：2
- reviewed_at：2026-09-21 21:16 UTC+8

## Round 2 (2026-09-21 21:16 UTC+8)

reviewed_scope: f4e6a4140554b220

## Findings

无新 finding。

## 结论

- 前轮 finding 复核：评审目录在本轮前没有 `review_code.md`，因此无可读取的前轮代码 finding；本轮按完整 diff 独立复核。t009 测试评审中的覆盖项属于 test reviewer 职责，不在本报告重复定级。
- 本轮新发现：0 条。
- 未进表的提示：无。实现文件均未达到文件过大阈值；未发现超出任务范围的代码改动、安全输入拼接、资源泄漏或高复杂度函数。
- 总体判断：卸载列表、预览、确认、唯一性校验、执行前重列、失败摘要与取消生命周期均符合契约。
- 系统性 follow-up：无。

### AC 复验方式

- AC-001：`re_verified`；`UninstallApp.CodingKeys` 解码 `name`、`bundle_id`、`uninstall_name`、`path`（`src/zmole/Features/Uninstall/UninstallSnapshot.swift:13-18`），`UninstallView` 展示四字段（`src/zmole/Features/Uninstall/UninstallView.swift:72-79`）。
- AC-002：`re_verified`；预览调用固定传入 `uninstall --dry-run <uninstall_name>` 与 `Data("y\\n".utf8)`（`src/zmole/Features/Uninstall/UninstallViewModel.swift:143-146`、`src/zmole/Features/Uninstall/UninstallViewModel.swift:297`）。
- AC-003：`re_verified`；生产调用只位于确认流程（`src/zmole/Features/Uninstall/UninstallViewModel.swift:176-233`），预览完成前没有生产 argv。
- AC-004：`re_verified`；生产 argv 为 `uninstall <uninstall_name>`，未拼接 `--permanent`（`src/zmole/Features/Uninstall/UninstallViewModel.swift:212-215`）。
- AC-005：`re_verified`；`canPreview` 要求恰好一个选择，`selectedTarget` 对无选择返回错误，预览按钮同步禁用（`src/zmole/Features/Uninstall/UninstallViewModel.swift:23-25`、`src/zmole/Features/Uninstall/UninstallViewModel.swift:258-263`、`src/zmole/Features/Uninstall/UninstallView.swift:87-91`）。
- AC-006：`re_verified`；确认后执行无 `--dry-run` 命令并传入确认输入，页面渲染成功摘要或错误摘要（`src/zmole/Features/Uninstall/UninstallViewModel.swift:212-233`、`src/zmole/Features/Uninstall/UninstallView.swift:114-125`）。
- AC-007：`re_verified`；预览前按当前列表统计 `uninstallName`，重复名称返回 `uninstall.error.ambiguous`，不发起 mole 调用（`src/zmole/Features/Uninstall/UninstallViewModel.swift:258-266`）。
- AC-008：`re_verified`；切换选择立即清除 preview，`canConfirm` 要求选择集合与 preview 一致（`src/zmole/Features/Uninstall/UninstallViewModel.swift:101-110`、`src/zmole/Features/Uninstall/UninstallViewModel.swift:27-33`）。
- AC-009：`re_verified`；确认执行前重新获取 list，并按完整行身份查找目标且再次要求 `uninstallName` 唯一；目标消失或 path 变化均返回 `changedTarget`（`src/zmole/Features/Uninstall/UninstallViewModel.swift:197-207`）。
- AC-010：`re_verified`；预览非零退出统一转为 `MoleBridgeError.commandFailed`，清除 preview 并展示失败信息（`src/zmole/Features/Uninstall/UninstallViewModel.swift:148-161`）。
- AC-011：`re_verified`；listing、preview、execution 均有忙碌门禁，确认后设置 `isExecuting`，取消调用 Bridge `cancel()` 并通过取消错误结束状态（`src/zmole/Features/Uninstall/UninstallViewModel.swift:55-69`、`src/zmole/Features/Uninstall/UninstallViewModel.swift:113-139`、`src/zmole/Features/Uninstall/UninstallViewModel.swift:237-240`）。独立运行 `xcodebuild ... test`：49 tests，0 failures。

coverage = 11 / 11

verdict: PASS
