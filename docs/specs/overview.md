# 概览与存储估算（overview）

- 来源 task：t016、t026、t034、t036、t044、t051、t058
- 生效范围：概览页与磁盘五段估算
- 最后更新：2026-10-18

## 行为契约

- 概览复用共享 `StatusViewModel` 采样：健康卡（健康分圆环 + 状态文案 + 三个指标 tile）、状态四宫格（CPU/内存/温度/网络）数值来自真实采样；数据缺失显示占位，不伪造数值或趋势。健康分不可用显示占位而非 0。状态功能停用时，健康评分与四宫格显式展示「已停用」，不将旧快照或历史数据作为实时值展示。
- 概览磁盘容量使用独立的轻量卷容量查询（`VolumeCapacityProviding`），在概览进入与刷新时读取，不依赖 `status-go`；状态功能停用期间容量与五段目录估算仍正常更新与展示，容量查询失败显示未知。
- 页头右侧「刷新」触发状态重采样与磁盘容量更新，「清理」入口跳转清理页；快捷卡区块与趋势条已移除。健康卡的可回收 tile 来自后台清理扫描的最新结果；无结果显示「暂无清理数据」，不自行估算。
- 存储卡：已用容量大数字、五段分段条与带数值图例；估算不完整时如实标明。
- 五段估算与统一测量：概览估算接入统一 `DiskMeasurementSession`，与磁盘分析共享测量事实并受 `HeavyScanScheduler` 准入。一次 `/Users` 遍历同时获取包含 Developer 的用户总量与 Developer 命名子树统计，消除独立重遍历与旧 `estimatePool` / analyze 目录命令通道。
- 分类归属规则：Developer 子树优先归属；跨 Developer 与其他用户路径的硬链接在 users 范围只计一次且归属 Developer；用户数据为 users 范围总量减 Developer 贡献（非负且相加等于 users 总量）。
- 渐进分段发布：分段计算完成立即可见并更新卡片；应用段完成即显示数值；用户段在 users 与 developer 均就绪后计算；系统段（排除 `/System/Volumes`）在全部必要子项成功后发布（任一子项失败则系统段不可用，绝不展示部分和）；所有分段齐备前「其他」段与未就绪段保持占位未知，不用 0 代替。
- 触发：进入概览即启动目录扫描，不等 status 采样；status 迟到只更新「其他」段（不重扫）；写入失效信号与缓存过期触发全量重算。估算任务由 ViewModel 持有，离开页面不取消。
- 缓存：`~/Library/Application Support/zmole/storage_estimate.json`（含 schemaVersion/capturedAt，当前版本 3）。进入概览先用缓存即时渲染；完成的扫描（含部分段）即展示并落盘；缺失段显示占位、保留「估算不完整」标记，并自动补扫一次（只探测缺失段）。补扫只探测缺失/失效项，中间进度事件不刷新未重新测量输入的 `capturedAt`；超过 TTL（6 小时）或收到写入失效信号时全量重算；超过最大年龄（7 天）或 schema 不符即作废（schema 1/2 的旧缓存全部丢弃重算）。写入失效落在扫描在飞期间时，即使该次扫描完整结束也保留失效状态，并自动补排一次全量重扫；补偿扫描期间无新失效才清除标记。
- 被取消的扫描（应用退出）或旧世代事件不写缓存。
- 无完全磁盘访问权限（FDA）时不扫描 `/Users` 段：该段留空占位、估算标「估算不完整」、概览显示授权横幅（打开系统设置 / 重新检测）；无 FDA 时允许单独测量可读的 Developer 子树。授权后回到概览自动全量重扫。FDA 检测读系统 TCC 数据库，不读内容、不触发系统弹窗。
- 概览四张卡片（健康、存储、最近活动、系统状态）统一固定高度。
- 最近操作复用 `history --json`：有记录显示标题与时间，空显示空态；history 失败在概览顶部显示错误 banner 与重试（不再静默）。
- 页面无 eyebrow 小字（标题下直接内容）。

## 验证

- `tests/unit/OverviewTests.swift`、`tests/unit/OverviewCacheTests.swift`、`tests/unit/OverviewLayoutTests.swift`
- `tests/unit/EstimateWorkQueueTests.swift`
- `tests/unit/OverviewUnifiedMeasureTests.swift`
