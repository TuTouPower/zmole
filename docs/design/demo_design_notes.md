# zmole UI/UX v2 — 设计说明

## 设计命题

zmole 不是“系统优化仪表盘”，而是把 CLI mole 的高风险系统操作包装成 **可预览、可理解、可确认** 的 Mac 工具。

本版吸收参考图中的三种有效模式，但不照搬：

1. **高密度应用列表 + 行内展开**：用于卸载，减少 inspector 来回跳转。
2. **状态卡片 + 进程表格**：只放在“状态”这个天然需要密度的页面，而不是首页。
3. **目录列表 + 空间可视化**：把 CleanMyMac 的空间感和 WinDirStat/WizTree 的面积编码合成一个更安静的“空间地图”。

## 信息架构

全局只保留 5 个工作模式：

- 清理
- 软件（卸载 / 白名单）
- 优化（维护 / Purge）
- 分析（只读）
- 状态（实时 / 历史）

这样避免首版 8 个功能全部平铺在侧栏，同时没有丢掉任何产品能力。

## 设计语言

- **系统组件感**：窗口、工具条、搜索、分段控件、列表、表格保持 macOS 熟悉感。
- **不做品牌色灌满窗口**：品牌只用在选择、可清理空间和数据强调上。
- **单一 signature element**：分析页的“空间地图”。面积是真数据含义，不是装饰。
- **危险操作不放到底部作为唯一入口**：选中对象后出现工具条下方 selection shelf，主要动作始终在上半区可见。
- **密度按任务变化**：清理与优化更克制；软件与状态更高密度；分析专注二维空间关系。

## HIG 映射

- macOS 允许高信息密度，但仍保持舒适扫描；窗口可缩放。
- 顶部工作模式是导航；当前页动作留在 view toolbar。
- 软件页的筛选栏只是上下文筛选，不承担全局导航。
- `Analyze` 不提供删除动作，符合项目第一版边界。
- 破坏性动作先预览，再使用明确动作名确认，不用模糊的“确定”。
- 支持 light/dark 语义 token、hover、keyboard focus、reduced motion。

## SwiftUI 落地建议

- 顶层：`TabView` 或自定义 toolbar 中的 `Picker(.segmented)`，由 App 状态控制五个工作模式。
- 软件页：`NavigationSplitView` 只在这个功能内部使用，左侧是筛选集合，右侧是 `Table`/`List`。
- 应用展开：`DisclosureGroup` 或 selection + inline detail section。
- 分析页：左侧 `List`，右侧自定义 `Layout`/Canvas 画 treemap；禁止放 destructive action。
- 状态页：上层 summary views + `Table` 进程列表。
- 设置：原生 `Settings` scene。
- 确认：`.alert` / sheet，按钮名称用“清理所选项目”“移到废纸篓”“开始执行”等具体动词。
