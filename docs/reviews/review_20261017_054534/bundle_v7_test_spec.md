# 视角7 — 测试·规格

## 范围与摘要

- 范围：tests/unit（32 个 Swift 文件 + .gitkeep）、tests/integration（clean_trash_test.sh、installer_interface_test.sh、uninstall_stream_test.sh）、tests/e2e（仅 .gitkeep）；对照 src/zmole/\*.swift 阅读；HEAD 94170aa0b8c980ec61a0e3498b5af15fce1379b + 未提交改动（AppIconTests.swift、scripts/build_app_icon.sh、scripts/svg_to_png.swift、StorageEstimateCache.swift 等）。
- 审查方式：只读（Read/rg/git），未执行 build/test/xcodebuild。
- 注意：审查期间工作树在持续编辑（OverviewView.swift / SidebarView.swift / UtilityUI.swift 在会话中被改动，AppIconTests.swift 修改时间 05:33），本报告行号以写入时磁盘内容为准。
- 摘要：整体测试工程扎实——协议边界 mock、fixture 多来自 spike 样本、集成脚本用隔离 HOME 调真实捆绑脚本、无 XCTSkip/恒真断言/注释掉断言；异步等待多为有界轮询。共 16 条 finding（C 0 / H 0 / M 7 / L 7 / Info 2），最重的是测试文档虚报覆盖、交接文档过期、spec 索引全空、一处 flaky 固定 sleep 与 clean 执行闸门的内容变化分支无测试。
- 说明：docs/specs_index.md 无任何生效 spec，故规格对齐以 docs/blueprint/\*、docs/design/ui_contract.md、docs/handoff.md 与归档任务 spec（只读参照，不作为 finding 对象）为准。

## Findings

- [M][85] docs/blueprint/testing.md:54 — 文档虚报 StatusStreamTests 覆盖面，真实 status 暂停/离页停止无行为测试 — 证据：该句称 StatusStreamTests「验证首帧渐进字段、暂停/恢复、离页停止、断流和磁盘 I/O warming」，但 tests/unit/StatusStreamTests.swift 全部 5 个用例只覆盖首帧缺字段、零值、网络聚合、共享流与有界趋势、断流重试；:72 的 service.stop() 在 2 个订阅者下被 src/zmole/Features/Status/StatusWatchService.swift:127 的 guard subscribers.count \<= 1 直接 no-op，唯一单订阅者 stop 在 :99 无任何副作用断言，pause() 从未被调用；离页停止映射 src/zmole/App/AppShellView.swift:117-121 无任何测试 — 修复：为真实 StatusWatchService 增补单订阅者 pause/恢复与 stop 取消流的用例（断言 streaming.cancel 或 streamCallCount），并为 destination→start/stop 映射抽可测纯函数补测；或改写 testing.md:54 该句避免虚报。
- [M][75] docs/handoff.md:11 — 项目交接记录严重过期，与主干状态矛盾 — 证据：handoff 落款 2026-09-21T16:00:00+08:00、head_commit 903b633e，正文仍写「未完成：Xcode 工程、捆绑 mole、各功能页、图标与 zip」，而 git log 显示已到 94170aa，t001–t039 全部归档 done，各功能页/图标/发布脚本均已落地 — 修复：按 AGENTS.md 用当前 branch：main 与 head_commit：94170aa 重写最新一节，将 2026-09-21 节迁 docs/archive/handoff.md。
- [M][70] docs/specs_index.md:5 — spec 索引全空，需求级 spec 未按流程累积 — 证据：表头（:5）下无任何数据行（「在表即生效」），docs/archive/specs/ 为空，而 git log --oneline 显示多批 task merge 已收尾；需求追溯只能依赖归档 task 目录，索引无法反映任何生效需求 — 修复：为已收官行为补写 docs/specs/<slug>.md 并填索引行；若有意不维护需求级 spec，应在该文件与 AGENTS.md 写明并说明替代追溯方式。
- [M][60] tests/unit/UninstallDetailTests.swift:105 — 固定 100ms sleep 等 unstructured reveal Task，慢机 flaky — 证据：src/zmole/Features/Uninstall/UninstallViewModel.swift:267-269 的 revealInFinder 内部 `Task { await revealer.reveal(...) }` 不可等待，测试以 `try? await Task.sleep(100ms)` 后立刻断言 paths == [app.path]（:107-108）；同仓对同类 fire-and-forget 用轮询：tests/unit/DiskExplorerTests.swift:363-368（200×5ms 有界等待）— 修复：改为同样的有界轮询等待，或让 revealInFinder 返回可 await 的 Task 供测试直接等待。
- [M][65] tests/unit/CleanPreviewStoreTests.swift:33 — clean 执行闸门「列表内容被改写」分支无测试 — 证据：CleanPreviewStore.verifyUnchanged 的 `guard contents == snapshot.contents`（src/zmole/Features/Clean/CleanPreview.swift:130）无用例触发；现有 3 个测试只覆盖 headers-only、删文件、文件变目录（:4-47）；同长度内容被覆盖时 confirmExecution 是否拒绝未验证 — 修复：新增用例把 clean-list.txt 改写为不同内容后走 CleanViewModel.confirmExecution，断言不 spawn `["clean"]` 且报 clean.error.changed_list。
- [M][55] tests/unit/AppIconTests.swift:46 — 字节级 icns 重现有跨工具链 flaky 风险且单元 target 承担重集成 — 证据：断言要求 scripts/build_app_icon.sh（现经 scripts/svg_to_png.swift + sips + iconutil，scripts/build_app_icon.sh:36 调用 swift 渲染）生成的 .icns 与仓库产物逐字节相等；PNG 编码/sips 行为随 macOS/Xcode 更新可变，图标仍有效时测试会误红；该用例还在每次单测 run 里做 bash+swift 编译，且 scripts/svg_to_png.swift 目前是 untracked 文件，一旦未随脚本提交，新克隆必失败 — 修复：改为解码级不变量断言（各尺寸存在、512 角透明、行列数），把字节一致性降级为发布校验；确保 svg_to_png.swift 与 build_app_icon.sh 同 commit 入库。
- [M][55] tests/integration/uninstall_stream_test.sh:8 — 命名卸载 `y\n` 确认协议无真实子进程测试 — 证据：集成层只测 `--list-stream`（本文件）与 clean/installer 路由；`uninstall <name>` 真实 stdin 行为只有 spy 字节断言（tests/unit/UninstallTests.swift:41 断言 stdin == Data("y\\n")），无法证明捆绑 uninstall.sh 在空 stdin 下安全中止；docs/handoff.md:12 恰将「空 stdin 可能误确认删除」列为陷阱 — 修复：新增集成用例，用夹具 app 分别以空 stdin 与 `y\n` 调真实 uninstall.sh（隔离 HOME），断言空 stdin 中止且原文件未动。
- [L][75] tests/unit/DiskExplorerTests.swift:371 — 多处「源码字符串包含」断言被当作行为验证，假阳/假阴风险 — 证据：同模式还有 tests/unit/UiAlignmentTests.swift:189-241（页面须含 MolePageHead(/isInfo: true 文本）、tests/unit/SettingsHistoryTests.swift:127（设置页不得含指定字符串）、tests/unit/CleanPageTests.swift:160（CleanView 不得含 "Toggle("）、tests/unit/OverviewLayoutTests.swift:128（无 quickCards/trendCard 文本）；约束靠 grep 生产源码实现，等价重构即假红，字符串出现也不证明渲染行为 — 修复：能抽 ViewModel/映射值的改断言数据（banner tone 已在 NoticeToneTests 覆盖），纯视觉约束保留最小集合并注明只防回归不证明行为。
- [L][60] tests/unit/NavigationTests.swift:72 — try? XCTUnwrap 吞错，且设置菜单测试名不副实 — 证据：:72 `let item = try? XCTUnwrap(...)` 后 `if let item { navigation.perform(item) }`，unwrap 失败时丢弃错误信息（仅靠 :76 间接兜底）；:33 testSettingsCommandSelectsSidebarSettingsPage 实际只调 navigation.select(.settings)，注释自认菜单接线不可测 — 修复：把该测试改为 throws 并用 `try XCTUnwrap`；菜单用例改名或标注为 select 行为测试。
- [L][60] tests/unit/OverviewCacheTests.swift:272 — schema 1→2 迁移路径无显式用例 — 证据：未提交改动把 StorageEstimateCache.schemaVersion 由 1 提升到 2（src/zmole/Features/Overview/StorageEstimateCache.swift:15，注释写明 schema-1 系统段含数据卷虚高），但唯一 schema 用例用 999 测「未知版本被忽略」（:272-277），没有构造 schemaVersion: 1 条目 — 修复：补 schema-1 条目 load(now:) == nil、primeEstimate 不采用旧值的用例。
- [L][70] tests/integration/installer_interface_test.sh:17 — setup_fixture 的 mktemp 工作目录从不清删 — 证据：setup_fixture 每次 `WORK="$(mktemp -d)"`，脚本尾部（:182-188）只做汇总退出；对照 tests/integration/uninstall_stream_test.sh:102 有 `rm -rf "$WORK"`；重复运行持续在系统临时目录泄漏 HOME/trash/zip 夹具 — 修复：加 `trap 'rm -rf "${WORK:-}"' EXIT` 或在 setup_fixture 开头清理上一次 WORK。
- [L][60] tests/e2e/.gitkeep — e2e 目录为空，视觉验收无入库证据 — 证据：tests/e2e 仅有 .gitkeep；docs/design/ui_contract.md:63 要求「交付实际运行 App 截图」且「视觉证据尚未形成前，不声明界面改版完成」；docs/blueprint/testing.md:36-45 的 blackbox_verify 是纯手工 `open -a` 流程；仓库内无 png/jpg 截图产物 — 修复：把验收截图入库（如 docs/reviews 或 docs/guides）并在相关任务收尾引用；若坚持人工验收，在 ui_contract/testing.md 明确证据存放位置。
- [L][50] tests/unit/MoleBridgeTests.swift:80 — 非流式聚合上限与 version() 空输出分支无测试 — 证据：src/zmole/MoleBridge/MoleBridge.swift:164 maxAggregateBytes = 16MB 的 outputLimitExceeded("stdout"/"stderr") 分支只被测到 1MB/1.1MB（本文件 :70-84、tests/unit/MoleStreamTests.swift:57-69），无超限用例；MoleBridge.swift:138 version() 抛 emptyOutput（src/zmole/MoleBridge/MoleBridgeError.swift:26）无测试 — 修复：各补最小用例（16MB 输出脚本、空 stdout 可执行文件）。
- [L][45] src/zmole/Features/Overview/StorageEstimate.swift:152 — 注释声称系统段等于 `analyze /System` 顶层和减 Volumes，与实现口径不一致 — 证据：:152 注释写「The value stays `analyze /System`'s top-level sum minus `/System/Volumes`」，但 systemSize() 实际对每个目录子项单独 analyze（:163-173），且 directoryChildren 过滤掉顶层文件（:118-131）；/System 顶层存在文件时两者不等 — 修复：注释改为「只读系统卷目录子项之和（不探测 /System/Volumes）」，或按注释口径改实现。
- [Info][45] tests/unit/ZmoleTests.swift:85 — 时间型断言依赖 demo 采样间隔 — 证据：`Task.sleep(2.7s)` 后断言 snapshot 非空且 isSampling，依赖 src/zmole/App/AppDependencies.swift:261 的 800ms 采样周期（余量约 3.4 倍）；高负载下首帧延迟理论上可失败 — 修复：改为带上限的轮询等待 snapshot 非 nil，保留后续 pause 断言。
- [Info][60] tests/unit/AppIconTests.swift:30 — 单测 target 依赖未被门禁登记的 bash/swift/sips/iconutil 工具链 — 证据：该用例经 Process 运行 scripts/build_app_icon.sh，脚本 :21 校验 `for tool in swift sips iconutil` 并编译渲染；docs/blueprint/testing.md 的 doctor_cmd（:11-17）只检查 md_kx/xcodebuild/xcodegen，未声明这些前置 — 修复：在 doctor_cmd 或该测试注释登记依赖，或在脚本内做前置检查给出可读错误。

## Spec Compliance

对照 docs/specs_index.md（空表，无生效 spec）、docs/blueprint/architecture.md、docs/blueprint/domain.md、docs/design/ui_contract.md、docs/handoff.md 与实际测试：

已覆盖且与 spec 一致：

- clean 预览快照语义（只认本次 dry-run、执行前校验未变、执行重扫提示文案）：tests/unit/CleanPreviewStoreTests.swift、CleanPageTests.swift、ZmoleTests.swift 覆盖；文案 claim（废纸篓）有测试。
- uninstall 身份唯一性、`y\n` stdin 字节、批量部分成功的未知态、目标自检、预跑复用名单：tests/unit/Uninstall\*Tests、BatchUninstallTests 覆盖（真实协议见 Findings [M][55]）。
- installer 非交互接口与删除目标自检、不重扫扫描根：tests/integration/installer_interface_test.sh 用真实 installer.sh + 隔离 Trash 覆盖。
- purge `--yes`、optimize 无子集、永久删除文案：OptimizePurgePageTests/PurgeTests/OptimizeTests 覆盖。
- disk 页应用内只读扫描、硬链接/符号链接/跨设备/不可读语义：DiskScannerTests/DiskExplorerTests 覆盖。
- prewarm 只读队列、单并发、不占写租约、写入/失效后重跑、demo 禁用：PrewarmTests 覆盖。
- 五段估算排除 /System/Volumes、缓存 TTL/最大年龄/不完整不落盘、部分缓存先渲染后覆盖：OverviewTests/OverviewCacheTests 覆盖。
- 命令通道分 lane、写互斥、busy 可恢复：CommandConcurrencyTests/RecoverableBusyTests 覆盖。
- testing.md 的 doctor_cmd/test_cmd 与实际仓库脚本一致：.repo_template/tests（pytest contract）、三个 integration 脚本、xcodegen/xcodebuild 均存在，未发现命令与实际不符。

缺失/部分实现：

- status 暂停/恢复与离页停止（architecture.md:75）无真实服务级测试；testing.md:54 的覆盖声明与事实不符（见 Findings [M][85]）。
- 概览页头「刷新」按钮与清理入口的 View 接线无断言，仅 OverviewTests 对 resample()/spy 计数（ui_contract.md:26）。
- 命名卸载 `y\n` 协议无真实子进程测试（见 Findings [M][55]）。
- 视觉类 AC（ui_contract.md:47-63 验收矩阵）无入库证据、无 UI 测试 target（见 Findings [L][60]）。
- 需求级 spec 无累积（specs_index 空表，见 Findings [M][70]）；项目级交接文档过期（见 Findings [M][75]）。
- 未发现「实现与 spec 硬冲突」的项；唯一口径不一致是 StorageEstimate.swift:152 注释与实现（Findings [L][45]）。

## 无发现声明

- 危险模式 4 类启发式均未命中：tests/ 全目录 rg 无 XCTSkip、#if false、XCTAssertTrue(true)、注释掉的断言或 disabled 测试。
- mock 使用规范：spy/fake 仅出现在协议边界（MoleProcessControlling/MoleStreaming/文件 store/OperationCoordinator/时钟 now 注入），未发现 mock 被测逻辑本身或被测对象与断言同源的自证（fixture 来自独立常量或 spike 样本）。唯一「断言对象与实现同源」类风险是源码字符串断言，已记 [L][75]。
- 改测历史（git log -p -- tests/）未发现就地改预期迁就实现：UninstallTests/ZmoleTests/RecoverableBusyTests/OverviewTests 的删除与改造都有注释写明语义迁移理由，替换用例覆盖新语义；OverviewTests 系统段用例期望值不变、仅 fixture 结构随接口变化。
- 集成脚本隔离良好：独立 HOME、mktemp 目录、MOLE_TEST_TRASH_DIR/MOLE_INSTALLER_SCAN_ROOT 注入，不触碰真实用户文件或 ~/.config/mole。
- 异步等待多为有界轮询（100-500 次×1-10ms），唯一定长 sleep 等待未结构化 Task 的点已记 [M][60]；其余定长 sleep 为负向断言窗口（PrewarmTests.swift:57 等）或 demo 时序（ZmoleTests.swift:85），风险低。
- 未发现测试直接 spawn 越界（真实 mole 破坏性命令）或依赖 PATH 中 `mo` 的行为。
