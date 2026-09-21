# 领域模型

命名以本表为准；UI 文案可中英对照，标识符用英文。

|术语|英文|含义|
|---|---|---|
|Mole CLI|`mo` / mole|上游开源命令行工具；本 App 的能力来源|
|桌面壳|zmole App|本仓产物：SwiftUI macOS 应用|
|桥接层|MoleBridge|调用 `mo` 并解析输出的进程适配层|
|干跑|dry-run|只预览将删除/变更的项，不落盘修改|
|白名单|whitelist|用户保护、禁止自动清理/优化的路径或规则；存 mole 配置|
|清理|clean|清缓存、日志、残留等可回收空间项|
|卸载|uninstall|移除 App 及其关联文件|
|优化|optimize|刷新缓存、有限维护任务（DNS、Spotlight 等）|
|磁盘分析|analyze|交互式/列表式磁盘占用浏览；危险操作确认后进废纸篓|
|状态|status|只读系统健康看板（CPU/内存/磁盘/网络等）|
|工程产物清理|purge|删除可重建的构建产物（如 `node_modules`、`target`）|
|安装包清理|installer|查找并删除 DMG/PKG 等安装包|
|操作历史|history / oplog|mole 记录的清理等操作日志|
|健康分|health score|status 给出的综合健康评分（只读）|

## 非目标（当前）

- 不实现与商业版 Mole for Mac 对等的全部 GUI 功能。
- 不在本仓 fork 并维护一份独立清理引擎；CLI 行为变更跟上游。
- 不默认捆绑或修改上游 mole 二进制许可范围之外的分发方式（若捆绑，须符合 GPL-3.0 与上游要求）。
