# p020 磁盘扫描 SQL 重复全表扫描导致持续占用约三个 CPU 核心

- 现象：2026-10-18T05:52:39+08:00，生产 Release 进程 PID 89390 启动约 5 分钟后仍占 290%–294% CPU；5 秒线程采样显示三个 utility worker 活跃，主线程多数等待事件。无活跃 CLI 子进程；应用持有一个发布库及三个暂存测量库。
- 影响：磁盘页与概览共享的原生测量后端。现场暂存库分别已有约 4.5 万 / 2.4 万 / 2.4 万条 entries，约一万目录/库；扫描与最终统计阶段均会大量消耗 CPU，延迟结果发布。性能回归由 `b391e81` 引入；此前 399 项测试通过不能证明真实规模下性能合格。
- 根因：产品性能缺陷，已现场复现。`DiskSessionStore.nextUnlistedDirectory` 对全部 entries 做过滤、排除已访问路径并排序，每读取一个目录重做一次；现场 `EXPLAIN QUERY PLAN` 明确包含 `SCAN entries` 与 `USE TEMP B-TREE FOR ORDER BY`，采样中两个 worker 分别有 321/442、289/442 个样本落在该查询。另一个 worker 全部 442 个样本落在 `recalculateAll → recalculate → selfTotal → sqlite3_step`，逐目录重复读取子树事实并执行挂载边界关联查询。
- 已确认同类位点：`recalculateAll` 每取一个目录都重新按 `length(path)` 排序；`selfTotal` 为每个目录分别聚合整棵子树并执行 `reachable` 反查；`contribution` 同样使用子树与挂载边界关联查询，属于需一并检查的统计路径，但本次采样未证明其为当前热点。修复须同时处理工作队列取项和最终统计，不能只把默认并发从 3 改小。
- 测试缺口：既有扫描与新增回归测试偏重小目录、正确性和驻留计数，没有覆盖数万 entries / 上万目录规模，也没有查询计划或 SQL 工作量上限断言。应增加触达生产 SQLite 扫描路径的规模夹具，分别约束逐项领取、底向上统计及挂载边界查询成本；保留硬链接去重、Developer 归属、跨设备排除、取消及时性、事务回滚与有界驻留覆盖。最终以修复前后相同只读夹具重复对照，再对真实只读运行采样验证。
- 线索：`.scratch/cpu_diagnosis/zmole_sample.txt` 为现场原始采样；`query_plan.json` 为只读提取、脱敏后的库规模与查询计划。源码：`DiskScanner.swift:169–183`，`DiskSessionStore.swift:212–216`、`:250–286`。未向正在运行的数据库写入任何内容，未另启高负载复现。
- 修复：2026-10-18T13:33:37+08:00，按用户授权在 main 直接修复。独立扫描队列、后序单游标、直接子项汇总与 inode 归并替换重复全扫；取消通过 SQL progress handler 响应。新增四项回归测试，全量 403 项、模板 contract 和四条集成通过；10,240 真实目录夹具三轮合计一致，17.7–18.7 秒完成。新 Universal Release zip 已通过签名、架构与解压包只读 CLI 验收。详细证据见 `docs/reviews/review_t045_onward/cpu_regression_fix.md`。
- 处理：main
