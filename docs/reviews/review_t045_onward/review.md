# t045 起始提交审阅

审阅基线：`ef087c3^..d436847`，16 个 commit（t045–t058、集成及 handoff）。记录时间：2026-10-18T05:41:03+08:00。用户授权在 `main` 直接修复。

## 发现

以下为基线缺陷；修复状态与验证结果见末节。

|编号|级别|来源|问题、触发与影响|
|---|---|---|---|
|R01|P1|t056|磁盘全树仍由 `LiveDiskScanner.walk` 返回；`records`、`subtreeFactsMap` 无淘汰，LRU 只统计 `childCache`，单目录也可超预算；批流无背压。大目录会持续膨胀内存，现有测试只查部分计数，未覆盖生产扫描。|
|R02|P1|t056|`clearSubtree` 把三条 DELETE 交给单次 prepare/step，实际只执行第一条；LIKE 把路径中的 `%`、`_` 当通配符。刷新后残留条目与 inode，且可能误清其他目录。保存快照不删除旧行，忽略 SQL 写入错误及 WAL 大小，存储失败仍发布成功结果。|
|R03|P1|t052/t048|磁盘 worker 忽略 acquire 取消错误，随后仍创建非结构化测量 Task；取消不能覆盖等名额阶段，旧 worker 可继续遍历。listing 在 await 后才捕获 generation，迟到旧列表可写入新世代。订阅取消也未正确移除队列需求。|
|R04|P1|t058|`measureSubtreeOutcome` 把首层 listing 的部分合计当完成事实；概览 TTL、写入失效与授权后重算没有使会话事实失效，反复取得旧值。会话扫描取消后 loader 未检查取消仍可返回并保存部分结果。|
|R05|P1|t052/t058|会话对整树统一使用根 `isReadable`，掩盖内部不可读目录；Developer 缺失/不可读统一回退 0；独立扫描跨设备子目录后，重算会把它计入父目录。|
|R06|P1|t048|`AppDependencies` 创建共享 scheduler，却未传给 `AnalyzeViewModel`；磁盘及复用它的概览使用另一调度器，总并发可超 3。页面调用未提升/撤回优先级。|
|R07|P1|t057/t047|hydration 只按 capturedAt 合并，可能复活失效前缓存；持久化的 stale 结果重启后不立即补扫。存储 load 合并字典无法表达已删除项；普通 debounce 落盘后服务水位不再更新。|
|R08|P1|t049|卸载首次流失败后保留已解析渐进行；`isListing=false` 即允许卸载，未要求成功完成名单。共享结果更新未清理选择、关联文件与图标状态，成功删除后也可能被旧服务快照重新覆盖。|
|R09|P1|t049|安装包后台名单替换不清除旧选择/确认，旧确认可作用于新身份；后台失败不反馈错误。删除期间的无关服务通知会重新采纳旧缓存名单。|
|R10|P1|t047|卸载、优化、项目清理在取消、超时等异常退出后未标记数据影响；clean 的取消入口也可先释放未标记 lease。已部分修改磁盘却没有发出刷新事件。|
|R11|P2|t046|NavigationModel 未在策略变化但目的地不变时通知界面；AppShell 在 @Published willSet 阶段读取旧策略，开启时可能仍走停用分支；迟到停用任务可覆盖新开启状态。|
|R12|P2|t051/t058|ProbeAggregator 写死 `/Applications`、`/Users`，忽略初始化注入路径，真实后端基准可能完成却未生成分段；现有性能测试只断言轮数。|

## 验证计划

先补回归测试触达生产对象，验证上述失效、SQL、取消与身份边界；再修复，并执行 Swift 全量测试、四条 Bash 集成测试、模板 contract 门禁及 Release 构建。破坏性命令仅用夹具。

## 修复

R01–R12 已修复。主要落点：

- [磁盘会话](../../../src/zmole/Features/Analyze/DiskMeasurementSession.swift)、[生产遍历](../../../src/zmole/Features/Analyze/DiskScanner.swift)、[SQLite 存储](../../../src/zmole/Features/Analyze/DiskSessionStore.swift)：分批暂存、事务发布、磁盘待办队列、全局空间配额、实际退出计账、世代隔离及有界驻留。磁盘页接入全量检索与分页，空间图合并其余条目。
- [概览估算](../../../src/zmole/Features/Overview/StorageEstimate.swift)：完整重算先使会话事实失效；必要目录不可读保持未知；使用注入路径聚合；取消后抛出取消信号。
- [App 装配](../../../src/zmole/App/AppDependencies.swift)、[窗口壳](../../../src/zmole/App/AppShellView.swift)：磁盘、概览和后台共享同一调度器，随目的地提升及撤回可见需求优先级；策略变更下一 MainActor 周期读取最新值。
- [后台服务](../../../src/zmole/Features/Operations/BackgroundScanService.swift)、[串行存储](../../../src/zmole/Features/Operations/BackgroundScanStorage.swift)：失效前缓存不得覆盖内存新值及删除；重启立即补扫 stale 结果并恢复版本水位；debounce 落盘更新服务水位，flush/close 提交最新内存快照。
- [卸载名单](../../../src/zmole/Features/Uninstall/UninstallViewModel.swift)、[安装包名单](../../../src/zmole/Features/Installers/InstallersViewModel.swift)：只有完成且有效名单可执行；刷新取消恢复稳定快照；新名单撤销旧选择与确认；执行期间不采纳旧缓存。
- clean、uninstall、optimize、purge 在交出执行控制前标记可能修改数据；取消、超时与读取失败均触发失效。busy、找不到入口及启动失败清除此标记，避免把未启动命令当写入。

## 回归证据

[ReviewRegressionTests.swift](../../../tests/unit/ReviewRegressionTests.swift) 覆盖生产对象与调用链：

|发现|回归场景|
|---|---|
|R01|单宽目录预算；真实文件系统遍历后分页访问全部 21 项，检索非驻留项|
|R02|路径含 `_` 不误清兄弟目录；清理全部表；快照替换删除旧行；事务超配额回滚保留旧快照|
|R03|等待名额时取消不得启动遍历；迟到 listing 不写回新世代；取消直到 walker 退出才释放状态及名额|
|R04|首层部分合计不能当完成结果；失效后再次测量得到新值|
|R05|独立卷测量不进入父合计；不可读 Developer 保持未知；既有真实硬链接测试继续通过|
|R06|生产装配使用 LiveDiskScanner，且 scheduler 与 App 调度器为同一实例|
|R07|持久化 stale 结果启动即刷新；hydration 期间删除有效；debounce 自动更新服务水位|
|R08|首轮名单失败不能执行渐进行；刷新取消恢复旧稳定名单|
|R09|同路径新 installer 身份撤销原确认与选择|
|R10|取消 purge 后 affected versions 递增且 lease 释放|
|R11|目的地不变时策略变化仍通知 NavigationModel|
|R12|自定义 Applications / Users 路径实际产生分段|

原测试处理：

- 删除 `DiskExplorerTests.testDiskSourcesDoNotRunMoleCommands` 整个测试。该测试把不带 scheduler 参数的构造表达式写成固定字符串，无法验证共享装配。新增运行时装配测试检查真实 scanner 与共享调度器身份；既有只读页面、Finder 和目录导航测试保留。
- 删除 `DiskMeasurementSessionTests.testAC003_CancellationPreventsNewStartsAndLateResultsDiscarded` 整个测试。其断言要求 blocked walker 尚未退出时立刻 `isScanning=false`，与同一 AC 的实际退出要求冲突。新增取消生命周期测试同时检查取消期间仍忙碌、名额继续持有、实际退出后释放，以及旧结果未发布。没有就地翻转旧测试预期。

## 验证结果

- Swift 全量：399 项通过，0 失败；包含新增 22 项审阅回归测试。
- 模板 contract：146 项通过、1 项跳过、367 项 deselected。
- Bash 集成：`clean_trash_test.sh`、`installer_interface_test.sh`、`uninstall_stream_test.sh`、`brew_cask_index_test.sh` 全部通过。
- Release：Universal 构建通过；主程序包含 `x86_64 arm64`，`codesign --verify --deep --strict` 通过。
- `git diff --check` 通过；工程由 `xcodegen generate` 生成。

本地运行日志位于 `.scratch/review_t045/`，不入库。

验证边界：未执行真实用户目录大规模 RSS / I/O 压测，也未执行三语、双外观、双尺寸 UI 截图矩阵。破坏性操作仅使用夹具，未执行真实清理或卸载；未发布。
