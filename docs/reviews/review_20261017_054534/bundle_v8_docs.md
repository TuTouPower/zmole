# 视角8 — 文档规范

## 范围与摘要

- 范围：README.md、AGENTS.md、docs/ 当前文档（blueprint/design/findings/pending/specs_index/handoff/plan.md/spikes/s001 report）、.opencode/commands/；以当前磁盘状态（HEAD 94170aa + 未提交改动）为准，代码作对照。
- 权威规范：`DOCUMENTATION_STANDARD.md`（三态划分、权威与证据、单一权威、载体合规）。仓库另有 `.repo_template/docs/usage.md` 的 md_kx 格式门禁，本次以 `md_format.py --check` 静态核对。
- 方法：逐文件通读 + 文档断言对代码/SOURCE_VERSION/补丁/任务归档逐条核对 + 相对链接与行号引用实测 + `.opencode/commands` 与 skills 一一对照。
- 摘要：无 C/H；文档层主要问题是「实现已全面落地、实施期文档未同步」——handoff/plan/refactor_grilling/pending 停留在落地前状态，testing/domain/architecture 有已被实现推翻的现在时陈述；另一类是 ui_contract 的重复行与视觉权威（绿色 vs 蓝色）内部冲突。blueprint 占位符结论见文末。
- 计数：C=0 / H=0 / M=10 / L=9 / Info=2。

## Findings

- [M][95] docs/handoff.md:5 — 交接记录过期近一个月，仍称「可 start t001」并列出未完成项 — 证据：该节时间 2026-09-21T16:00，head_commit 903b633e（2026-09-21「docs: lock v1 scope and create backlog tasks」），正文「未完成：Xcode 工程、捆绑 mole、各功能页、图标与 zip」「下一步：同意后提交本批 backlog」；实际 t001–t039 已全部归档（docs/archive/tasks/），HEAD 94170aa 为 2026-10-17 — 修复：repo-hygiene 将该节迁 `docs/archive/handoff.md`，写新一节（branch/当前 head_commit/剩余工作：终验与 Release）。
- [M][90] docs/plan.md:36 — 第一版计划已被完全实现取代，文件仍以现在时呈现且含已推翻断言 — 证据：line 36「不做（已 park…）：installer、analyze 删除…」但 installer 已实现（architecture.md 安装包接口 + src/zmole/Features/Installers/，t022/t023 归档）；Backlog t001–t013 全部归档（line 56–70）；README.md:7 仍把它链接为「实现计划」 — 修复：计划文本标历史（或迁 archive），README 改指向 `docs/blueprint/`。
- [M][85] docs/blueprint/domain.md:17 — 领域术语「状态」定义为「只读健康快照（非 live watch）」，与实现相反 — 证据：生产路径 `StatusWatchService` 运行 `mole status --watch --interval`（StatusWatchService.swift:146），architecture.md:75「状态流」也写 live watch；domain.md 仍写「非 live watch」 — 修复：改为实时 watch 契约（只读、可暂停、离页停止）。
- [M][90] docs/blueprint/testing.md:32 — 模板落地前措辞与现状矛盾（自相矛盾于同文件命令块） — 证据：line 9「完整 Xcode…在工程落地后纳入本检查；当前本机若仅有 Command Line Tools，不在此硬失败」、line 21「落地前…写『无』」、line 32「当前阶段以模板工具链测试为主；业务 Swift 测试随首个实现 task 接入」；但同文件 test_cmd 已含 `xcodebuild test` 且 tests/unit 有 30+ 测试文件、工程已生成 — 修复：删除三处落地前残留，改为当前门禁描述。
- [M][85] docs/blueprint/architecture.md:14 — 模块划分表与实况不符 — 证据：`Models` 行称「命令结果、预览条目、白名单行等值类型」，实际 src/zmole/Models/ 仅 .gitkeep、值类型散在 MoleBridge/Features；line 12 Features 列表缺 Overview、Installers、Settings、Confirmation、Operations（src/zmole/Features/ 实有 13 个目录 + 2 个文件） — 修复：按实际目录重写模块表。
- [M][95] docs/design/ui_contract.md:27 — 页面契约表「清理」行重复且两行内容不一致 — 证据：line 27 与 line 29 同为清理行，line 29 额外含「打开页面直接显示后台预跑预览与扫描时间」 — 修复：删 line 27，保留含预跑条款的一行。
- [M][80] docs/design/ui_contract.md:7 — 契约自称以 HTML 为「视觉权威」，正文（未提交改动）却改按蓝色，权威声明未同步且无决策记录 — 证据：line 7 宣布视觉权威为 mole_desktop_demo_cn_final.html（其 `--accent:#2f8f68`/暗色 `#58b889` 为绿色）；line 18 改后写「蓝色（与应用图标一致的蓝系）」；MoleTheme.swift 未提交 diff 将 accent 由绿 `0x2F8F68` 改蓝 `0x0072FF`；decisions.md 001–008 无此变更条目 — 修复：更新参考资料声明（或补 decisions 条目说明 accent 改跟图标）。
- [M][80] docs/design/refactor_grilling.md:32 — 「已核对的事实」多条已被本次重构/实现推翻，文件未标历史/替代且被 ui_contract 当权威引用 — 证据：line 32「清理走 safe_remove 直接 rm -rf…没有环境变量能把清理改成移到废纸篓」已被 t017 补丁推翻（file_ops.sh:1256 `_mole_clean_trash_path`、user.sh:37 停用 clean_trash）；line 33「安装包…现在是永久删除」已被 t022 接口推翻；line 42「t014 还在 backlog」实际已 dropped 归档；line 7「还没有改产品代码」已不成立；ui_contract.md:7 仍称其为「决策清单」 — 修复：文件头加「2026-10-16 决策记录，已被实现取代」标注并指向现行权威。
- [M][85] docs/pending/parked/p001_installer_gui.md:3 — 条目前提已被实现推翻 — 证据：正文「`mo installer` 无 JSON/`--yes`…第一版不做 installer」，但捆绑 installer 已加非交互接口（installer.sh:829 `zmole local patch (t022)`，InstallerInterface.swift:61/77 调 `--list-json`/`--remove`），页面已交付（Features/Installers/）；「来源 grilling Q17」与仓库内唯一 grilling 文档 refactor_grilling.md 的 Q17（卸载字段）冲突 — 修复：archived 或改写为未来增强，并复核来源引用。
- [M][65] docs/specs_index.md:1 — 声明「task 收尾时累积 spec」，39 个 task 全部归档后需求级 spec 从未累积 — 证据：docs/specs/、docs/archive/specs/ 均只有 .gitkeep，本表为空；AGENTS.md:9-10 把该机制列为当前约定 — 修复：补写需求级 spec 行，或在 AGENTS.md/本文件声明该机制本仓未启用。
- [L][90] README.md:40 — 开发段命令整段注释且标「（落地后）」，工程已落地 — 证据：line 40-42「# 工程由 XcodeGen 生成（落地后）：# xcodegen # xcodebuild …」，而 testing.md:16/24 已把 `xcodegen generate`/`xcodebuild` 列为现行门禁；project.yml 与 Zmole.xcodeproj 均已存在 — 修复：改为可执行的当前构建步骤（含 xcodegen generate）。
- [L][85] docs/blueprint/conventions.md:15 — 目录约定列落地后结构，与实际不符 — 证据：line 15「`src/zmole/Models/` — 共享模型」实际为空目录（仅 .gitkeep）；line 34-42 提及 `schemas/`、`config/`、`docs/schemas/`，仓库中均不存在 — 修复：按现状更新目录清单，未用落点注明当前未启用。
- [L][85] docs/spikes/s001_mole_cli_fixtures/report.md:1 — 已关闭 spike 未按约定迁档 — 证据：plan.md:56 标「s001（已关闭，结论见 d001）」，AGENTS.md:18 规定「完结由 repo-hygiene 迁 docs/archive/spikes/」，但 s001 仍在 docs/spikes/（该目录按定义只放当前 spike） — 修复：repo-hygiene 迁档并同步 d001 的 samples/ 引用路径。
- [L][75] docs/findings/d001_mole_cli_machine_surfaces.md:12 — 证据行号随补丁漂移、研究克隆已不存在，引用不可复核 — 证据：`bin/uninstall.sh` 确认提示原在 1767 行（52da180 快照），t029 补丁后现为 1887；`~/kar/github_repo/mole` 本机已不存在 — 修复：更新为当前捆绑树行号，或注明「行号随捆绑补丁漂移，按符号 `match_apps_by_name`/`Proceed with uninstallation?` 定位」。
- [L][85] docs/design/refactor_grilling.md:561 — 相对路径指向已归档目录 — 证据：line 561「`docs/tasks/t014_refine_app_visual_design/`」，docs/tasks/ 现仅 .gitkeep，t014 在 docs/archive/tasks/ — 修复：更新为 archive 路径或改写为叙述。
- [L][70] docs/design/demo_design_notes.md:15 — 旧版五模式导航文档保留原文但文件自身未标过时 — 证据：line 15「全局只保留 5 个工作模式」，已被 ui_contract.md 十页侧边栏取代；demo_design_system.md:303、370 同样以现在时写五模式与 1200×760/880×620 尺寸（ui_contract 为 1200×780/1100×700）；过时状态仅在 ui_contract.md:7 标注，未落到文件本身 — 修复：两文件头部加「已被 ui_contract.md 侧边栏基线取代」标注。
- [L][60] docs/design/refactor_grilling.md:560 — 承诺的 optimize 白名单 ADR 未落地 — 证据：line 560 承诺「decisions.md 追加安装包机器接口和 optimize 白名单两条」，现 decisions.md 仅 001–008，008 为安装包接口（line 62-69），无 optimize 白名单条目 — 修复：补 ADR 或在文件中注明该条不再需要。
- [L][55] README.md:9 — 公共下载页未写最低系统要求 — 证据：README「运行时」节（line 9-14）无 macOS 版本，而 decisions.md:42/plan.md:11 锁定 macOS 13+；README 是唯一公开入口 — 修复：在运行时节补「macOS 13+」。
- [L][55] AGENTS.md:16 — 仍声明 architecture/domain 是未填充占位符 — 证据：原文「`architecture.md` / `domain.md` 是模板仓占位符…未填充前不视为权威」，实际两文件已完整填写项目内容（99/30 行项目专属事实），该句与仓库状态矛盾，易使读者低估其权威 — 修复：改为已填充说明。
- [Info][40] docs/design/ui_contract.md:3 — 「实现状态：进行中，尚未通过视觉验收」需复核 — 证据：实现该基线的 t035–t039 已全部关闭（t036 done，t037–t039 dropped 并入 t035），t036 review 自述视觉截图无法独立核验（docs/archive/tasks/t036_ui_overview_align/review_general.md:57）；当前状态语句是过期还是仍成立（全矩阵未验收）需维护者确认 — 修复：按验收实况重写该行。
- [Info][40] docs/pending/parked/p004_sparkle_autoupdate.md:6 — parked 条目「暂搁」理由为复制粘贴的通用句 — 证据：p001–p005 第 6 行均为「第一版确认不做：无稳定机器接口或会破坏捆绑 App / 需开发者账号」，与各条实际阻塞（如 Sparkle 的更新源/签名、公证的账号）不完全对应 — 修复：按条目写明真实阻塞。

## 死链与锚点核查

相对链接/路径引用逐项实测（`rg` + 文件系统核对）：

|出处|引用|结果|
|---|---|---|
|README.md:7,30,31,32|docs/plan.md；AGENTS.md；.repo_template/docs/usage.md；docs/blueprint/|存在（plan.md 内容过时见 Finding M）|
|docs/design/ui_contract.md:7|mole_desktop_demo_cn_final.html；refactor_grilling.md；demo_reference.html；demo_design_system.md；demo_design_notes.md|全部存在|
|docs/design/refactor_grilling.md:561|docs/tasks/t014_refine_app_visual_design/|失效（已迁 docs/archive/tasks/，见 Finding）|
|docs/findings/d001:12|docs/spikes/s001…/report.md、samples/、lib/clean/project.sh 1682/2518、bin/uninstall.sh 1767|report/samples/project.sh 行号 1682、2518 仍命中所述 purge 逻辑；uninstall.sh 1767 漂移至 1887（见 Finding）|
|docs/spikes/s001…/report.md:18|.scratch/s001/home|已不存在（scratch 清理，历史证据不可复核）|
|AGENTS.md:12-16,18,25-26|docs/archive/handoff.md、archive/tasks、archive/specs、archive/pending、.repo_template/scripts/{task,pending,findings,spikes}.py、.repo_template/docs/usage.md、.repo_template/docs/architecture.md、docs/spikes/{sid}\_{slug}/code/|全部存在（s001 无 code/，按「有实验代码才建」不构成缺失）|
|docs/blueprint/conventions.md:28-30|assets/app_icon_source.svg、app_icon_source_mono.svg、scripts/build_app_icon.sh、scripts/svg_to_png.swift、project.yml、Info.plist `CFBundleIconFile`|全部存在且一致|
|docs/blueprint/testing.md:12-30|.repo_template/tests、tests/integration/{clean_trash,installer_interface,uninstall_stream}\_test.sh、scripts/build_release_zip.sh、ZmoleTests target|全部存在（target 名与 project.yml 一致）|
|docs/plan.md:34|docs/pending/parked/|存在|
|docs/specs_index.md:3|docs/archive/specs/|存在（空）|
|docs/handoff.md:3|docs/archive/handoff.md|存在|
|docs/pending/parked/\*.md|无相对链接|—|
|外部链接（README mole.fit、tw93/mole，architecture.md:97，refactor_grilling.md:5 的本地 Downloads 来源）|未做网络核验|按规范仅静态记录；本地绝对路径来源不可移植|
|heading anchor 链接|全量检查无 `#` 锚点形式的跨文件链接|无失效锚点风险|

## 无发现声明

以下项经核对未发现违规：`.opencode/commands/` 15 个命令文件与 `.claude/skills/` 15 个 skill 一一对应、描述逐字一致，无流程漂移（命令文件均自带「Auto-generated…Do not edit directly」）；全部范围内 Markdown 通过 `python3 .repo_template/scripts/md_format.py --check`（格式一致）；文档与示例无凭据/弱默认 secret、无未定义占位符（仅 refactor_grilling 读法相关的过时说明）；README 功能声称与实现逐条一致（捆绑 V1.55.0/69ab325d 与 SOURCE_VERSION 一致、analyze-go/status-go 经 lipo 双架构、不装 PATH、三语跟随+设置覆盖、Gatekeeper 步骤）；ui_contract 页面契约抽查与实现一致（命令面板仅导航 NavigationModel.swift:14-23、清理阶段名无百分比 CleanScanStage.swift:3、卸载/预跑/磁盘/window metrics AppDestination.swift:88-93、settings 字段）；architecture.md 抽查一致（8 条一次性通道 MoleCommandLanes.swift:53、预跑顺序 PrewarmService.swift:9-15、估算缓存 TTL 6h/上限 7 天/schemaVersion 2 StorageEstimateCache.swift:15-19、watch 离页停止 AppShellView.swift:116-123、demo 不启预跑 MoleCommandLanes.demo）；testing Release 脚本描述与 build_release_zip.sh 行为一致；pending p002–p005 的非目标仍成立（仅 p001 失效）；decisions 001–006 与现行实现不冲突。blueprint 占位符结论：architecture.md、domain.md 均已填充为项目专属内容，不是模板占位符；AGENTS.md:16 的「占位符/未填充不视为权威」表述对本仓已过时（见 Finding L）。
