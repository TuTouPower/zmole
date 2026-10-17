# 领域模型

命名以本表为准；UI 文案三语对照，标识符用英文。

|术语|英文|含义|
|---|---|---|
|zmole|zmole App|本仓产物：SwiftUI macOS 窗口应用|
|捆绑 mole|bundled mole|打进 `.app` 的钉死版本 CLI 树；唯一运行时|
|桥接层|MoleBridge|spawn 捆绑 mole 并解析输出|
|干跑|dry-run|只读，不落盘修改|
|白名单|whitelist|`~/.config/mole/whitelist` 为受保护路径，`~/.config/mole/whitelist_optimize` 为优化任务 id；两者均可在设置编辑|
|清理|clean|清缓存、日志、已卸 App 残留；删除移入废纸篓，且同一次不再清空废纸篓；不能按界面勾选子集执行|
|卸载|uninstall|移除 App 及关联文件；默认进废纸篓；名单先出、大小随后补上；确认复用会话名单|
|后台扫描|background scan|应用运行期间并行执行的只读扫描（卸载名单、安装包名单、clean/optimize/purge dry-run）；结果落盘并按 24 小时刷新；不占写入租约，clean 与用户扫描/执行互斥|
|优化|optimize|有限维护（DNS、Spotlight 等）；其中删除保持永久删除|
|磁盘分析|disk|只读浏览占用；应用内扫描，不调用 mole；文件按 `st_blocks × 512`，硬链接同一扫描只计一次，符号链接只计自身，跨设备子目录不计入父合计；会话内保留已扫描层级；第一版不在浏览结果上删除|
|状态|status|实时只读 watch 流（`status --watch --interval`）；可暂停、离页停止，流错误终态需手动重试|
|工程产物清理|purge|删除可重建构建产物；非 TTY 执行必须 `--yes`|
|安装包|installer|扫描下载中的安装包；非交互列出后按路径移入废纸篓|
|操作历史|history|mole 操作日志|
|健康分|health score|status 给出的综合分|
|五段估算|storage estimate|概览的 系统/应用程序/用户数据/开发者/其他 估算；系统段只计只读系统卷（`/System` 顶层排除 `/System/Volumes`）；完成的扫描（含部分）即展示并落盘，缺失段占位并保留「估算不完整」标记、自动补扫一次；被取消的扫描不落盘|

## 第一版非目标

- analyze/磁盘页删除、嵌终端、代按键驱动 TUI
- 捆绑 mole 的 self-update / remove
- 把 `zmo`/`mo` 装进 PATH
- Sparkle、Apple 公证、Mac App Store、遥测
- 对标 Mole for Mac
