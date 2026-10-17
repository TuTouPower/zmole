# Task review t046（reviewer_focus: 代码）

- task：`t046_settings_toggle_status_feature`
- spec：`docs/tasks/t046_settings_toggle_status_feature/spec.md`
- diff_anchor：`ef087c3f87c740b1cdd748062adf376f9d68e780`
- target：`git -C '/Users/karson/kar/code/zmole_t046' diff ef087c3f87c740b1cdd748062adf376f9d68e780`
- round: 1
- reviewed_at: 2026-10-17T23:50:00+08:00

reviewed_scope: 915e5a92799d1cc9

## Findings

Round 1 零 finding。

## 结论

- 本轮新发现：0 条
- 未进表的提示：无
- 总体判断：代码设计清晰，`StatusFeaturePolicy` 统一管理状态功能开关，生命周期与持久化严密。`NavigationModel` 隐藏与防跳转、`StatusViewModel` 全入口前置拦截与异步进程终止、`OverviewView` 的独立轻量卷容量查询（`VolumeCapacity`）及停用降级均已完整落实，无资源泄漏与时序漏洞。
- 系统性 follow-up：无

### AC 复验方式

- AC-001：`re_verified`，查证 `StatusFeaturePolicy.swift` 默认开启且以 `UserDefaults` 持久化，`SettingsView.swift` 提供带三语文案的开关。
- AC-002：`re_verified`，查证 `NavigationModel.swift` 隐藏侧边栏与命令面板项，并在 `select` 中拒绝受限跳转。
- AC-003：`re_verified`，查证 `NavigationModel.swift` 监听开关并在停用时将 `.status` 重定向至 `.overview`。
- AC-004：`re_verified`，查证 `StatusViewModel.swift` 在 `start()`、`retry()`、`resample()` 均校验 `isFeatureEnabled`，`applyPolicyChange` 停止并等待底层进程退出。
- AC-005：`re_verified`，查证开启后入口恢复且重新开始实时采样。
- AC-006：`re_verified`，查证 `OverviewHealthCard.make` 与 `OverviewStatusGrid.make` 在停用时显示「已停用」与「—」。
- AC-007：`re_verified`，查证 `StatusViewModel.swift` 的 `watchTask` 在启动前与更新循环中均核验 `isFeatureEnabled`，在途启动不会复活。
- AC-008：`re_verified`，查证 `VolumeCapacity.swift` 与 `OverviewViewModel.refreshDiskCapacity()` 独立读取卷容量，不启动 `status-go`。
- AC-009：`re_verified`，查证 `AppShellView.swift` 仅在当前可见页为概览或状态时启动采样，其他页面不启动。

coverage = 9 / 9 (100.0%)

verdict: PASS
