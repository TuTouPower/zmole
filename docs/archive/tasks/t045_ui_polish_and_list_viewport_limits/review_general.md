# Task review t045（reviewer_focus: 通用）

- task：`t045_ui_polish_and_list_viewport_limits`
- spec：`docs/tasks/t045_ui_polish_and_list_viewport_limits/spec.md`
- diff_anchor：`bf5e8602a91df70c8b2cf9c4dd3c11c0a916c83d`
- target：`git -C '/Users/karson/kar/code/zmole_t045' diff bf5e8602a91df70c8b2cf9c4dd3c11c0a916c83d`
- round: 1
- reviewed_at: 2026-10-17T23:35:00+08:00

reviewed_scope: 241cee0df6df92a2

## Findings

Round 1 零 finding。

## 结论

- 本轮新发现：0 条
- 未进表的提示：无
- 总体判断：实现与 AC 契约严格对应，侧边栏副标题、角标与采样圆点已完全清理且无死依赖；四页长列表/输出与固定操作区分离，视口结构清晰无嵌套滚动冲突；设置页底色统一为 `MoleTheme.background`；单元测试与回归测试全绿。
- 系统性 follow-up：无

### AC 复验方式

- AC-001：`re_verified`，查证 `SidebarView.swift` 增加 `withoutSystemFocusRing()` 并在 macOS 14+ 禁用系统焦点框，单元测试 `testSidebarSuppressesSystemFocusRingAndStylesThemeFocus` 覆盖。
- AC-002：`re_verified`，查证 `SidebarView.swift` 的 brand 移除 `app.tagline`，单元测试 `testSidebarBrandDropsTagline` 覆盖。
- AC-003：`re_verified`，查证 `SidebarView.swift` 移除 `lastReclaimBytes`，单元测试 `testSidebarDropsCleanReclaimBadgeAndStatusDot` 覆盖。
- AC-004：`re_verified`，查证 `SidebarView.swift` 移除状态采样点与 ViewModel 绑定，单元测试覆盖。
- AC-005：`re_verified`，查证 `InstallersView.swift` 将候选列表放入独立 `ScrollView`，外层移除全屏滚动，全选/清空工具栏与底部移除按钮常驻视口。
- AC-006：`re_verified`，查证 `OptimizeView.swift` 将任务行与原始输出收敛于卡片内部 `ScrollView`，执行按钮固定于卡片底部视口。
- AC-007：`re_verified`，查证 `PurgeView.swift` 将输出放入内部 `ScrollView`，执行按钮固定于卡片底部视口。
- AC-008：`re_verified`，查证 `HistoryView.swift` 的 `headerRow` 固定、数据行由内部 `ScrollView` 独立滚动，页头与导出/刷新常驻。
- AC-009：`re_verified`，查证 `SettingsView.swift` 添加 `.scrollContentBackground(.hidden)` 与 `.background(MoleTheme.background)`。
- AC-010：`trust_prior`，依赖 Demo UI smoke 验收与单元测试布局模型验证。
- AC-011：`re_verified`，查证 `SidebarView.swift` 使用 `@FocusState` 与 `MoleTheme.accent` 轮廓高亮，焦点与选中态可明确区分。

coverage = 10 / 11 (90.9%)

verdict: PASS
