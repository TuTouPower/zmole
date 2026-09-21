# 领域模型

命名以本表为准；UI 文案三语对照，标识符用英文。

|术语|英文|含义|
|---|---|---|
|zmole|zmole App|本仓产物：SwiftUI macOS 窗口应用|
|捆绑 mole|bundled mole|打进 `.app` 的钉死版本 CLI 树；唯一运行时|
|桥接层|MoleBridge|spawn 捆绑 mole 并解析输出|
|干跑|dry-run|只预览，不落盘修改|
|白名单|whitelist|`~/.config/mole/whitelist` 中受保护路径；GUI 编辑此文件|
|清理|clean|清缓存、日志、已卸 App 残留；默认永久删，不进废纸篓|
|卸载|uninstall|移除 App 及关联文件；默认进废纸篓|
|优化|optimize|有限维护（DNS、Spotlight 等）|
|磁盘分析|analyze|只读浏览占用；第一版不在浏览结果上删除|
|状态|status|只读健康快照（非 live watch）|
|工程产物清理|purge|删除可重建构建产物；非 TTY 执行必须 `--yes`|
|操作历史|history|mole 操作日志|
|健康分|health score|status 给出的综合分|

## 第一版非目标

- installer、analyze 删除、嵌终端、代按键驱动 TUI
- 捆绑 mole 的 self-update / remove
- 把 `zmo`/`mo` 装进 PATH
- Sparkle、Apple 公证、Mac App Store、遥测
- 对标 Mole for Mac
