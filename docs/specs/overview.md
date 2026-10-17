# 概览与存储估算（overview）

- 来源 task：t016、t026、t034、t036
- 生效范围：概览页与磁盘五段估算
- 最后更新：2026-10-17

## 行为契约

- 概览复用共享 `StatusViewModel` 采样：健康卡（健康分圆环 + 状态文案 + 三个指标 tile）、状态四宫格（CPU/内存/温度/网络）数值来自真实采样；数据缺失显示占位，不伪造数值或趋势。健康分不可用显示占位而非 0。
- 页头右侧「刷新」触发状态重采样，「清理」入口跳转清理页；快捷卡区块与趋势条已移除。
- 存储卡：已用容量大数字、五段分段条与带数值图例；估算不完整时如实标明。
- 五段估算：`/Applications`、`/System` 顶层子项（排除 `/System/Volumes`）、`~/Library/Developer`、`/Users` 减开发者、其他 = 全盘已用 − 四段之和（负值按 0）。任一输入缺失该段为空占位，不填演示常量。探测经 3 条估算通道并发执行（单通道串行）。
- 缓存：`~/Library/Application Support/zmole/storage_estimate.json`（含 schemaVersion/capturedAt）。进入概览先用缓存即时渲染（「其他」用实时 status 已用现算）；后台仅在缓存缺失、超过 TTL（6 小时）或收到写入失效信号时重算并回写。超过最大年龄（7 天）或 schema 不符即作废（schema 1→2 的旧缓存全部丢弃）。
- 只有完整扫描（四个路径全部可读）才落盘并接替当前估算；扫描被取消或缺少任一路径时不写缓存、不替换已展示结果；失败后进入冷却（30 分钟）再重试，避免持久失败路径导致每次进页重扫。
- 最近操作复用 `history --json`：有记录显示标题与时间，空显示空态；history 失败在概览顶部显示错误 banner 与重试（不再静默）。
- 估算退出页面（`.task` 取消）后不得写缓存；离开页面立即停止等待。

## 验证

- `tests/unit/OverviewTests.swift`、`tests/unit/OverviewCacheTests.swift`、`tests/unit/OverviewLayoutTests.swift`
