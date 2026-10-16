# 领域模型

命名以本表为准；UI 文案三语对照，标识符用英文。

|术语|英文|含义|
|---|---|---|
|zmole|zmole App|本仓产物：SwiftUI macOS 窗口应用|
|捆绑 mole|bundled mole|打进 `.app` 的钉死版本 CLI 树；唯一运行时|
|桥接层|MoleBridge|spawn 捆绑 mole 并解析输出|
|干跑|dry-run|只预览，不落盘修改|
|白名单|whitelist|`~/.config/mole/whitelist` 为受保护路径，`~/.config/mole/whitelist_optimize` 为优化任务 id；两者均可在设置编辑|
|清理|clean|清缓存、日志、已卸 App 残留；删除移入废纸篓，且同一次不再清空废纸篓；不能按界面勾选子集执行|
|卸载|uninstall|移除 App 及关联文件；默认进废纸篓；名单先出、大小随后补上；预览/确认复用会话名单|
|预跑|prewarm|空闲时的后台只读扫描队列（卸载名单、安装包名单、clean/optimize/purge dry-run）；不占写入租约，写入开始即取消|
|优化|optimize|有限维护（DNS、Spotlight 等）；其中删除保持永久删除|
|磁盘分析|disk|只读浏览占用；应用内扫描，不调用 mole；文件按 `st_blocks × 512`，硬链接同一扫描只计一次，符号链接只计自身，跨设备子目录不计入父合计；会话内保留已扫描层级；第一版不在浏览结果上删除|
|状态|status|只读健康快照（非 live watch）|
|工程产物清理|purge|删除可重建构建产物；非 TTY 执行必须 `--yes`|
|安装包|installer|扫描下载中的安装包；非交互列出后按路径移入废纸篓|
|操作历史|history|mole 操作日志|
|健康分|health score|status 给出的综合分|

## 第一版非目标

- analyze/磁盘页删除、嵌终端、代按键驱动 TUI
- 捆绑 mole 的 self-update / remove
- 把 `zmo`/`mo` 装进 PATH
- Sparkle、Apple 公证、Mac App Store、遥测
- 对标 Mole for Mac
