# 状态页与实时流（status）

- 来源 task：t004、t016（状态部分）、t037
- 生效范围：状态页、概览页的共享采样
- 最后更新：2026-10-17

## 行为契约

- 数据源为单条 `mole status --watch --interval 1s` 流；`StatusWatchService` 对订阅者 fan-out，维护有界趋势序列（60 点）。
- 指标区 4 格：CPU、内存、磁盘写入、温度；数值来自真实采样，不可用字段显示本地化的「未知」占位，不伪造 0。
- 系统负载图显示 CPU 与内存两条序列（最近 60 秒）；采样点不足时显示等待说明，不绘制伪造趋势。首帧慢字段缺失、磁盘 I/O warming 阶段以显式状态展示。
- 网络面板显示下载/上传速率（物理接口聚合，忽略虚拟接口）；首帧或 warming 显示采样中说明。
- 进程列表只读（无结束进程入口）；陈旧数据显式标记（badge）。
- 暂停：停止流并保留当前数据；恢复重新订阅。离页（切到非概览/状态目的地）停止流；快速切页时过期的启动被 generation 丢弃，不会在离页后复活 watch。
- 状态功能受全局唯一策略 `StatusFeaturePolicy` 约束：功能停用后，全部 start、retry、resample 入口均拒绝发起采样；关闭时立即终止底层 watch 进程并清除数据快照；隐藏侧边栏与命令面板入口，当前状态页自动重定向至概览；重新开启后恢复可访问性，仅在当前处于可见监控页时重新启动采样。
- 流断开/解析失败：页内保持最后一次快照并在顶部展示错误 banner 与「重试」（错误不再因快照存在而隐藏）。连续 3 行坏 JSON 才终止流；孤立坏行跳过。
- 流是终态设计：错误后仅手动重试重新启动；无自动重启循环。

## 验证

- `tests/unit/StatusStreamTests.swift`（编码、聚合、共享流、有界趋势、断流、pause/stop 取消流）
- `tests/unit/OverviewTests.swift`（StatusViewModel start/stop/resample）
- `tests/unit/ZmoleTests.swift`（demo 流采样）
