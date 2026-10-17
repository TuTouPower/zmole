# d002 macOS 目录元数据预取对象分配开销大于系统调用

- 来源：s002 (t050)
- 结论：在 macOS Swift 环境下，使用 Foundation URL 批量预取元数据（`contentsOfDirectory(at:includingPropertiesForKeys:)`）相比逐项 POSIX `lstat` 慢约 338%，对象分配与桥接开销显著超过系统调用节约。
- 证据：10 轮 AB/BA 交错基准测试表明：逐项 `lstat` avg=0.0115s，Foundation URL 预取 avg=0.0505s（慢 338.1%）。
- 影响：`LiveDiskScanner` 与统一磁盘测量会话保持逐项 `lstat` 读取，不迁移至 URL 预取。
- 现状：有效
