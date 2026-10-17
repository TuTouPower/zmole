# Spike report: s002 统一测量后端的元数据预取对照试验

## 问题

在 macOS/APFS 环境下，统一磁盘测量层 `LiveDiskScanner` 当前采用逐项调用 POSIX `lstat` 读取条目元数据（分配块、inode、linkCount、设备、目录标识）。是否有必要迁移至 Foundation URL 元数据枚举预取（`contentsOfDirectory(at:includingPropertiesForKeys:)`）？预取在语义等价性与实际吞吐量上是否有可测量的稳定收益？

## 成功判据

- 语义严格等价（AC-001）：包括 `st_blocks × 512` APFS 分配大小、符号链接不跟随、硬链接多引用标记与去重、跨设备边界识别、不可读目录与条目消失状态一致。
- 性能具备稳定收益（AC-004）：在包含宽目录（1000+ 文件）、深目录（15 层嵌套）、稀疏文件、多引用硬链接与符号链接的代表性夹具上，经至少 10 轮 AB/BA 交错测量，整体延迟稳定改善且无关键场景明显退化。

## 尝试

在 `docs/spikes/s002_metadata_prefetch_benchmark/code/benchmark.swift` 中构建了独立基准程序：

1. 逐项 `lstat` 适配器：基于 `contentsOfDirectory(atPath:)` 获取文件列表后对每个条目调用 `lstat`。
2. Foundation URL 预取适配器：基于 `contentsOfDirectory(at:includingPropertiesForKeys:)` 批量预取 `.isDirectoryKey`, `.isSymbolicLinkKey`, `.fileAllocatedSizeKey`, `.linkCountKey`；缺失字段进行定向补取。
3. 夹具包含 1000 宽目录、15 层深目录、10MB 稀疏文件（分配 4KB）、100 个多引用硬链接及符号链接。
4. 运行 10 轮交错重复测试并统计分布。

## 证据

语义核查（AC-001）：

- 两种方式在总大小（14,917,632 bytes）、可读性（true）、条目数（5 个根顶层）及符号链接不跟随上完全一致。

10 轮 AB/BA 交错重复测量（AC-004）：

- Round 1 (AB): Item=0.0108s | Prefetch=0.0495s
- Round 2 (BA): Item=0.0117s | Prefetch=0.0497s
- Round 3 (AB): Item=0.0123s | Prefetch=0.0510s
- Round 4 (BA): Item=0.0115s | Prefetch=0.0506s
- Round 5 (AB): Item=0.0108s | Prefetch=0.0499s
- Round 6 (BA): Item=0.0115s | Prefetch=0.0518s
- Round 7 (AB): Item=0.0113s | Prefetch=0.0515s
- Round 8 (BA): Item=0.0118s | Prefetch=0.0507s
- Round 9 (AB): Item=0.0111s | Prefetch=0.0496s
- Round 10 (BA): Item=0.0126s | Prefetch=0.0509s

汇总统计：

- 逐项读取（`lstat`）：avg = 0.0115s, min = 0.0108s, max = 0.0126s
- 枚举预取（Foundation URL）：avg = 0.0505s, min = 0.0495s, max = 0.0518s
- 差异：枚举预取比逐项读取慢 338.1%（~4.4 倍耗时）。

原因分析：

1. Foundation `contentsOfDirectory(at:includingPropertiesForKeys:)` 在堆上为每个文件创建 `NSURL` 实例，并跨 ObjC/Swift 桥接字典包装资源属性，产生大量对象分配与引用计数开销。
2. 逐项读取使用 C POSIX `lstat`，直接填充栈上分配的 `struct stat`，无堆对象分配，字符串直接复用。
3. APFS 精确块大小 `st_blocks` 与 inode/device 标识在 Foundation 预取中缺乏直接对应数字键，仍需补取系统调用，未能完全消除 stat 调用。

## 结论

元数据枚举预取在 macOS Swift/Foundation 下存在显著的对象分配与桥接性能退化（耗时增加 338%），不具备采纳价值。保留当前生产 `LiveDiskScanner` 逐项 `lstat` 读取策略是最优、最高效的工程决策。

## 是否采纳

- 决定：否（保留生产逐项 lstat 读取，不采纳 Foundation URL 枚举预取）
- 理由：预取耗时较逐项读取增加 338%，对象分配开销远超系统调用节约。
- 后续 task：无（在 t050 内完成并固化结论）
