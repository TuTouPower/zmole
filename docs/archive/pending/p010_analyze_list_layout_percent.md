# p010 Analyze 页列表布局与百分比列改造

- 来源：用户 2026-10-17 口述，附 WizTree 截图参考
- 内容：Analyze（磁盘）页（`src/zmole/Features/Analyze/AnalyzeView.swift` + `AnalyzeViewModel.swift`）列表布局与人机交互改造，含以下子项：
    - 子项1 可拖动分隔线：左侧目录列表与右侧容量方块占用图之间的分隔线（`AnalyzeView.swift` 约 line 52 `directoryPane.frame(minWidth: 340)` 所在的 `HSplitView`/固定宽度 `HStack` 布局）改为可按住左右拖动，调节两侧宽度。
    - 子项2 移除按钮：删除左侧列表行靠右对齐的「进入目录」按钮（`AnalyzeView.swift` 约 line 185 的行内按钮，及 line 282 inspector 与 line 185 的 `Button("analyze.open_directory")`），不再提供独立按钮。
    - 子项3 双击进入：进入目录统一改为**双击**——左侧列表行双击、右侧容量方块双击都下钻进入该目录（复用 `AnalyzeViewModel.openDirectory(_:)`，`AnalyzeViewModel.swift` 约 line 89）；文件项不下钻；不改 Finder 打开入口 `analyze.reveal`/`revealInFinder`（`AnalyzeView.swift` line 284）。
    - 子项4 列布局：左侧列表把文件大小紧跟在文件名右侧（文件名列右侧），并**新增一列「占父目录大小百分比」**。
    - 子项5 百分比口径与呈现：按 WizTree 的 `% of Parent`（每项占**其父目录**总量百分比，而非占当前根），并在该百分比单元格内附**水平柱形条**（bar），长度按百分比。
- 参考：WizTree "Macintosh HD" Tree View——列 `Folder | % of Parent | Size | ...`，示例 `/ (Macintosh HD)` 100.0%、System 49.5%、Users 19.7%、Applications 13.3%、Library 9.5%、private 4.8%。截图本地留存 `.scratch/pending_refs/p010_wiztree_percent.png`（原路径 `/Users/karson/Library/Application Support/com.raycast.macos/clipboard/file-b67ebf5983fa156044d91956b3e0a2ba.png`，Raycast 剪贴板路径可能失效）。
- 边界：只针对 Analyze 页；百分比仅展示，不改变排序/分析逻辑；文件项不参与下钻。
- 处理：t032
