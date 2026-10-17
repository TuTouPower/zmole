# p016 侧边栏视觉细节与多余元素清理

- 来源：用户 2026-10-17 口述
- 内容：侧边栏（`src/zmole/App/SidebarView.swift`）人机视觉优化，含以下四项：
    1. **去除概览/导航项蓝色焦点框**：导航项按钮（`navItem` Button 及其 label）有时在获得焦点或点击时会显示系统蓝色边框（focus ring），需彻底去除/禁用焦点环样式（例如使用 `.focusable(false)` 或自定义无 focus ring 按钮样式）。
    2. **移除 App 副标题**：左上角 App 图标右侧的 `brand` 区块中，移除 `Text("app.tagline")`（"Mac系统维护"），仅保留粗体 App 名称。
    3. **移除清理按钮右侧预估大小**：`navItem` 中 `destination == .clean` 时右侧显示的 `cleanViewModel.lastReclaimBytes` 空间角标移除，保持导航栏条目清爽一致。
    4. **移除状态按钮右侧蓝点**：`navItem` 中 `destination == .status` 时右侧在采样期间显示的蓝色圆点（`Circle().fill(MoleTheme.accent)`）移除。
- 边界：仅修改侧边栏呈现，不破坏导航逻辑、目的地选择与快捷键；不改动各业务页内部实现。
- 处理：t045
