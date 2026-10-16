# 视角4 — 性能·资源

## 范围与摘要

- 范围：`docs/reviews/review_20261017_054534/_meta/scope_files.txt` 全量 152 文件，主体为 `src/zmole/*.swift`（按当前磁盘状态，含未提交修改），另含 `project.yml`、`scripts/build_*.sh` 的包结构效率。vendored `Resources/mole`、docs/archive、.repo_template、.claude/skills 已排除。
- 方法：只读静态审查（Read/rg/git），未构建、未运行、未跑基准；所有量级判断均为代码结构推断。
- 主题分布：MoleBridge 子进程/管道热路径 4 条；Analyze 扫描与视图重算 7 条；Uninstall/Clean/Overview 发布与缓存 8 条；其余渲染/内存/打包 6 条。
- 计数：C 0 / H 3 / M 10 / L 10 / Info 2，共 25 条。
- 最重三条：MoleBridge 逐字节加锁解析 stdout（MoleBridge.swift:427）；AnalyzeView 在每次子树测量发布时全量重筛重排（AnalyzeView.swift:37）；AnalyzeViewModel 把被测子树每一层的目录清单全部驻留并在主线程批量插入（AnalyzeViewModel.swift:221）。

## Findings

### H — 确定性能陷阱

- [H][80] src/zmole/Features/Analyze/AnalyzeView.swift:37 — 排序/筛选在视图 body 内执行，且每次子树测量完成都触发全量重排 — 证据：`visibleEntries`（第37-39行）每次渲染执行 `entries.filter` + `AnalyzeListOrder.sorted`（AnalyzeViewModel.swift:270-293，逐比较 `localizedStandardCompare`，ICU 级开销）；`@Published level` 在每次子目录测量完成时被重新赋值（AnalyzeViewModel.swift:233-235），即一层 N 个子目录 → N 次重排；`ForEach(visibleEntries)`（第213行）随之重建。进入含大量子目录的层（如 node_modules、/usr/local/bin 数千项）时总成本 O(N² log N) 级 ICU 比较 — 修复：把排序结果缓存到 AnalyzeViewModel（key = level generation + sort + search，或在 apply/publish 时增量维护有序数组），body 只读取缓存；搜索改为按需去抖。
- [H][78] src/zmole/MoleBridge/MoleBridge.swift:427 — 流式 stdout 解析逐字节获取 NSLock，O(字节数) 次锁操作 — 证据：`for byte in data {`（第427行）在 0x0A 分支（第429-435行）与非换行分支（第437-441行）各做一次 `lock.lock()/unlock()`；readChunkSize 64KB（第162行）→ 每块约 65,536 次锁往返，uninstall --list-stream / clean --dry-run 数 MB 输出即数百万次锁 + 逐字节 `Data.append`，都在 utility 队列上串行执行 — 修复：用 `memchr`/`data.split(separator: 0x0A)` 先切块，再一次性加锁处理整块；或把行缓冲移出共享锁（每通道独占状态）。
- [H][70] src/zmole/Features/Analyze/AnalyzeViewModel.swift:221 — 被测子树的每一层清单全部驻留内存，并在 MainActor 上批量插入 records — 证据：`measureSubtree` 返回 `levels: [String: DiskLevel]`（DiskScanner.swift:117-128，walk 对每个访问目录 `levels[path] = ...`，第254行）；`apply` 在 `for (path, scannedLevel) in result.levels`（第221行）里逐层 `records[path] = LevelRecord(...)`，全是主线程执行；进入 `~` 或 `/Users` 这类大目录时，records 会驻留整棵子树的目录项（每项含完整 path/name 字符串），十万级目录/百万级文件场景内存数百 MB，插入循环本身也会卡主线程数百 ms 起 — 修复：给 records 设容量/深度上限或按需惰性填充（进入目录时再 list），至少把批量插入移到后台构造好快照后一次性发布。

### M — smell / 边界 / 低频性能

- [M][85] src/zmole/Features/Clean/CleanViewModel.swift:117 — clean 预览文件读取+解析在 MainActor 同步执行 — 证据：`previewClean()`（@MainActor）在 dry-run 结束后 `let snapshot = try previewStore.read(generation)` 同步调用 CleanPreviewStore.read（CleanPreview.swift:76-112：`Data(contentsOf:)` + 整文件 `String` + split 出 entries + `CleanPreviewParser.sections`，第110行）；PrewarmService 同路径（PrewarmService.swift:212，同为 @MainActor）。clean-list.txt 可达 MB 级、数万行，解析期间主线程冻结 — 修复：`await Task.detached { try store.read(generation) }` 或改 async read。
- [M][80] src/zmole/Features/Uninstall/UninstallViewModel.swift:135 — 名单流每行都整表发布，触发视图逐行全量过滤+排序 — 证据：`listings = merged`（第135行）在 `for try await row in rows` 内逐行执行；identity + 完整两趟 → 每 app 约 2 次发布；UninstallView.visibleListings（UninstallView.swift:23-34）每次 body 重算 `UninstallListFilter.visibleListings` + `.sorted`（第27行 `localizedStandardCompare`）。500 app ≈ 1000 次发布 × 每次 O(N log N) ICU 比较 — 修复：按 50-100ms 节流/合并发布（或 ceil 到每 20 行一次），列表排序结果按 revision 缓存。
- [M][80] src/zmole/Features/Overview/StorageEstimate.swift:137 — 概览估算的多个独立目录探测全部串行，且 /System 子目录逐个 spawn analyze — 证据：`loadSums()` 顺序 await applications → system → developer → users（第137-140行）；`systemSize()` 对 `/System` 每个顶层子目录串行 `directorySize`（第163-173行），即 3 + N(/System 子项) 次独立 analyze 子进程首尾相接；每条在独立 estimate lane 上不可并发（MoleBridge 单 runner，MoleBridge.swift:75）。首次估算/缓存过期时墙钟 = 各次扫描之和，数十秒到分钟级 — 修复：为 estimate lane 分配多条 bridge 并用 `withThrowingTaskGroup` 并发跑各路径；起码让 /System 子项并行（2-4 并发）。
- [M][75] src/zmole/Features/Clean/CleanView.swift:131 — 清理预览全量行非惰性渲染 — 证据：`ForEach(preview.sections)`（第131行）套 `ForEach(section.entries)`（第133行）在 ScrollView + VStack 中展开，无 LazyVStack/List；clean dry-run 可达上万条，每行含图标+path+size+按钮全部实例化 — 修复：改 `LazyVStack` 或 `List`，entries 达到阈值时分行节流渲染。
- [M][70] src/zmole/Features/Analyze/AnalyzeView.swift:322 — 矩形树图布局在 GeometryReader body 内每次渲染重算，无 memo — 证据：`let tiles = SpaceMapLayout.tiles(...)`（第322行）位于 body 内；tiles() 做 filter+sort+递归 partition（SpaceMapLayout.swift:12-65）；每次测量发布（AnalyzeViewModel.swift:233-235）、每次选中/窗口 resize 都会全量重算，第317行 `drawable` 过滤同样在 body 内 — 修复：按 (entries 指纹, size) 缓存 tiles（@State + onChange 或放 ViewModel），resize 时仅在尺寸实质变化后重算。
- [M][70] src/zmole/Features/Uninstall/UninstallViewModel.swift:75 — canPreview 为 O(选中数×名单数)，被视图 disabled 状态高频求值 — 证据：`selectedPaths.allSatisfy { path in listings.contains { ... } }`（第75-77行）对每个选中 path 线性扫 listings；`.disabled(!viewModel.canPreview)`（UninstallView.swift:165）使每次渲染都执行；全选 500 项时约 25 万次比较/渲染，叠加上条逐行发布 → 数亿级比较 — 修复：用 `Set(listings.map(\.path))` 做 O(1) 查询，或在选择变化时预计算。
- [M][70] src/zmole/Features/Overview/OverviewViewModel.swift:332 — 部分失败的估算永不缓存 → 每次进入概览都重跑多子进程全量扫描，无退避 — 证据：`guard cacheEntry.sums.isComplete else { return true }`（第332行）使任一路径（如 /System 某子项权限失败）不可读时 `estimateNeedsRefresh` 恒真且 `computeEstimate` 不落盘（第376行 `guard sums.isComplete else { return }`）；OverviewView `.task` 每次出现在概览页都触发（OverviewView.swift:32-36）。若失败是持久的，用户每次回概览都重启一轮数十秒扫描 — 修复：为失败路径设置重试冷却（如 30 分钟 backoff）或缓存部分和并只重试失败路径。
- [M][65] src/zmole/Features/Uninstall/UninstallViewModel.swift:192 — 图标逐个发布触发逐图标整页重渲染，读取也是串行 — 证据：`iconsByPath[listing.path] = icon`（第195行）对 @Published 字典逐项赋值 → 每图标一次 objectWillChange，UninstallView 每次重算 visibleListings（UninstallView.swift:23）；`for listing in listings ... await iconProvider.icon`（第192-197行）顺序 await（LiveUninstallIconProvider 每图标一个 Task.detached，UninstallMetadata.swift:24-28）。500 app ≈ 500 次全页重排 — 修复：批量收集后每 N 个（或 100ms）一次赋值，或图标存非 @Published 容器 + 手动节流刷新。
- [M][60] src/zmole/Features/Analyze/AnalyzeViewModel.swift:192 — 子目录测量严格串行，CPU/IO 并行度闲置 — 证据：`processMeasurements`（第189-198行）`while let request = pendingMeasurements.first` 逐个 await `scanner.measureSubtree`；一层有几十个子目录时总时长 = 各子树扫描之和，界面「计算中」持续时间成倍拉长 — 修复：2-4 路并发（TaskGroup/信号量），保持每个 parent generation 的 apply 顺序即可（apply 已按 generation 校验）。
- [M][55] src/zmole/Features/Analyze/AnalyzeViewModel.swift:192 — 用户在测量进行中进入目录会导致同一子树被走两遍 — 证据：父层测量 `/Users` 在飞时用户双击进入，`showPath` 无记录 → `list(path)` 重新列目录并为子项入队测量；此时在飞测量不受影响（第190-196行 generation 校验只看 parent，不查子路径是否已有记录），旧的批量测量与新的逐子项测量都会 `measureSubtree` 同一子树，磁盘 IO 翻倍（结果的 records 写入由第222行 generation 比较去重）— 修复：measureSubtree 前先检查 records 是否已有该子路径的新鲜层（可复用则跳过），或取消同路径在飞测量。

### L — 风格 / 文档 / 低影响

- [L][85] src/zmole/Features/Analyze/DiskScanner.swift:228 — 目录遍历单线程递归，无并发枚举 — 证据：`walk` 递归（第197-256行），每目录一次 `contentsOfDirectory` + 每文件一次 lstat，全在单个 `Task.detached` 内（第117-128行）；深目录树（如整个 home）纯串行 IO — 修复：如需提速可对同层子目录做有限并发（4-8）或批量 `URLResourceKey` 枚举；当前可接受，仅记录。
- [L][85] src/zmole/MoleBridge/MoleBridge.swift:564 — 诊断尾巴缓冲用 `removeFirst` 逐块 memmove — 证据：`buffer.removeFirst(buffer.count - Self.diagnosticTailBytes)`（第564行）在超 64KB 后每个 chunk 触发约 64KB 拷贝（appendDiagnosticTail 被 consume 每 chunk 调用，第416/418行） — 修复：环形缓冲或 `buffer = buffer.suffix(limit)` 低频压缩。
- [L][85] src/zmole/Features/Status/StatusSnapshot.swift:355 — 每次解析时间戳都新建 ISO8601DateFormatter — 证据：`parseDate` 内 `let formatter = ISO8601DateFormatter()`（第355行）且可能两次设置 formatOptions 后重试；每个 status 样本解析 collected_at/process_collected_at 两次（第289-290行），1 Hz — 修复：静态复用两个 formatter（fractional / 无 fractional）。
- [L][80] src/zmole/Features/Settings/SettingsView.swift:135 — 每次 body 渲染都同步读捆绑 SOURCE_VERSION 文件 — 证据：`cliVersionText`（第134-136行）调用 `BundledMoleInfo.tag()`，内部 `String(contentsOf:)`（BundledMoleInfo.swift:17）读磁盘；SettingsView body 每次刷新都会执行 — 修复：一次性缓存（static let / @State + task 加载）。
- [L][75] src/zmole/Features/Whitelist/WhitelistViewModel.swift:55 — 配置类文件在主线程同步读 — 证据：`load()`（@MainActor）`try store.load()` 同步 `Data(contentsOf:)`（WhitelistStore.swift:39）；同类：PurgePathsViewModel.load（PurgePaths.swift:78-86）、HistoryViewModel.export 同步写（HistoryViewModel.swift:115）。文件均为 KB 级，影响小 — 修复：如后续文件变大，移入 detached task。
- [L][75] src/zmole/Features/Analyze/AnalyzeViewModel.swift:214 — 每个子目录完成都对全层 entries 重算合计，O(N²) — 证据：`parentRecord.totalSize = filesTotal + entries.reduce(...)`（第214-217行）在 N 个子目录测量完成时各扫一遍 N 项 — 修复：增量累加（apply 时只加/减该子项差值）。
- [L][70] src/zmole/Features/Optimize/OptimizeView.swift:8 — dry-run 输出每次 body 渲染都重新解析 — 证据：`rows` 计算属性（第8-11行）在 body 求值时调用 `OptimizePlanParser.rows(from: output)`（逐行 split+marker 匹配，OptimizePlan.swift:30-57）；输出十 KB 级、渲染不频繁，影响有限 — 修复：在 ViewModel 接受 preview 时解析一次并存储 rows。
- [L][70] src/zmole/Features/History/HistoryView.swift:105 — 历史表非惰性渲染且行 id 基于下标 — 证据：`ForEach(rows)`（第105行）在 ScrollView+VStack 中全部实例化（上限 200 行，HistoryViewModel.swift:39），`HistoryTable.rows` 每次 body 重建（第88行），行 id 为 "session-(index)"/"deletion-(index)"（HistorySnapshot.swift:64、75）在数据变化时会整体重打 — 修复：LazyVStack；id 改用日期+命令/路径等稳定值。
- [L][65] src/zmole/App/AppDependencies.swift:711 — 每个 @Published 变化都经 objectWillChange 派发一个 MainActor Task — 证据：analyze/uninstall/installers/clean 四个订阅（第711-722行）对每次发布 `Task { @MainActor in prewarm?.noteActivityChanged() }`；扫描期间可达数千次任务创建（配合 UninstallViewModel.swift:135、AnalyzeViewModel.swift:233 的高频发布） — 修复：合并/去抖（如 200ms 窗口或只在 isScanning 状态翻转时派发）。
- [L][65] src/zmole/Features/Clean/CleanPreview.swift:41 — 预览快照同时保留原始全文与解析后的两份表示 — 证据：`CleanPreviewSnapshot` 存 `contents`（整文件 String）＋ `entries`（去注释行数组）＋ `sections`（含 rawLine 复制，CleanPreviewModel.swift:4-16），同一数据 2-3 份驻留整个会话 — 修复：确认执行只需 contents 摘要时，可只保留解析结果或按需重读文件。

### Info — 观察

- [Info][80] src/zmole/Features/Operations/PrewarmService.swift:156 — 每次写操作成功后整个 5 项空闲扫描队列全部重跑 — 证据：`invalidateResults()`（第154-161行）`results.removeAll(); queue = PrewarmItem.allCases` 后 `poke()`；触发源 coordinator.$invalidationGeneration（第82-84行）。设计如此（architecture.md「空闲预跑」），但每次 clean/uninstall 之后都会在后台重扫卸载名单、安装包、clean/optimize/purge dry-run（各可达分钟级），属资源换响应速度的既定权衡 — 修复：如需降负载，可按项失效（只重跑与写入相关项）。
- [Info][60] src/zmole/Features/Status/StatusWatchService.swift:149 — status --watch 流无超时，卡死的 helper 会一直挂着 — 证据：`timeout: nil`（第149行）；流错误是终态且不自动重试（第158-164行，注释说明防重启风暴）。若 mole 进程挂起但不退出，仅表现为 UI 停在旧样本，无错误提示；进程在离页 stop() 时才回收 — 修复：可选加“样本静默超过 N 秒”检测并在 UI 标记（不自动重启）。

## 无发现声明

以下性能检查项已核查，未发现问题或确认无风险：

- 管道死锁：stdout/stderr 由独立 dispatch 队列并发读取，无 `readDataToEndOfFile` 顺序依赖、无 `waitUntilExit`，不存在经典管道缓冲死锁；stdin 仅写 `y\n` 后立即关闭，不会写阻塞。
- 无界输出：非流式 run 有每通道 16MB 上限并对超限显式报错（MoleBridge.swift:164、401-407）；流式事件队列有 256 上限；status 趋势序列有 historyLimit=60 上限；prewarm 结果集固定 5 项。未发现无界增长的消息/日志缓冲。
- symlink 循环：DiskScanner 用 lstat，符号链接不以目录身份递归，不会形成循环。
- 重复扫描（常规路径）：进入已测目录由 records 命中直接发布，不重读磁盘；「重新分析」只失效当前子树。
- Timer/KVO 泄漏：全仓无 Timer、无 KVO；Combine 订阅均 weak self 且随 owner 释放（AnyCancellable 由 VM/AppDependencies 持有）。
- ForEach id 稳定性：主要大列表使用 path/name 等稳定 id（DiskEntry.path、UninstallAppListing.path），除历史表用下标（已单列）外未见重建陷阱。
- 打包/构建脚本：project.yml 以 folder 引用捆绑 mole 树（dual-arch Go helper 16MB 必要），AppIcon.icns 为脚本生成产物、size 正常；build_release_zip.sh 无重复拷贝或把源码打进 zip 的问题。
- 图表重算：StatusLineChart 每样本重算 60 点路径，量级极小（1 Hz），不构成性能问题。
