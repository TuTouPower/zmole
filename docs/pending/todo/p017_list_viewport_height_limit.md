# p017 安装包、项目清理、历史记录与优化清理界面列表视口限高与内部滚动

- 来源：用户 2026-10-17 口述
- 内容：针对内容条目可能较多的四个功能界面，将其列表/输出内容限制在固定的最大高度视口内，超长时仅在列表区域内部滚动，避免整页垂直拉长导致底部的操作按钮与提示难以触达：
    1. **安装包（Installers）**：`src/zmole/Features/Installers/InstallersView.swift` 的 `listCard` 中，`ForEach(visibleCandidates)` 区域增加最大高度限制并嵌入可独立滚动的容器（或由外层 ScrollView 约束为内部滚动），确保底部的全选/清理操作栏始终固定或易于触达。
    2. **优化清理（Optimize）**：`src/zmole/Features/Optimize/OptimizeView.swift` 的 `planCard` 中，`ForEach(rows)` 任务列表增加最大高度限制，任务超长时在内部滚动，使底部的「执行优化」操作栏不被推到页面极深处。
    3. **项目清理（Purge）**：`src/zmole/Features/Purge/PurgeView.swift` 的 `outputPanel` 中，输出滚动区域（当前仅 `minHeight: 260`）增加 `maxHeight` 限制，使底部的「执行清除」按钮保持在可预期视口内。
    4. **清理历史记录（History）**：`src/zmole/Features/History/HistoryView.swift` 的 `HistorySnapshotContent` 表格区域增加合理高度限制与独立滚动，多行记录时避免无限撑高页面。
- 边界：只控制列表/内容区域视口约束与滚动行为，不改变列表项内容、过滤筛选与执行命令。
- 处理：未开
