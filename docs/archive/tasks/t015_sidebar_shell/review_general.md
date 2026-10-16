# Task review t015（reviewer_focus: 通用）

- task：`t015_sidebar_shell`
- spec：`docs/tasks/t015_sidebar_shell/spec.md`
- diff_anchor：`00814db3ebf3d6b288625cbbd167120f0b9205ce`
- target：`git -C '/Users/karson/kar/code/zmole_t015' diff 00814db3ebf3d6b288625cbbd167120f0b9205ce`
- round：1
- reviewed_at：2026-10-16T17:23:51+08:00

## 验证动作

- `git -C /Users/karson/kar/code/zmole_t015 diff 00814db3ebf3d6b288625cbbd167120f0b9205ce`（含 intent-to-add，未用 `...HEAD`）逐文件核对。
- `xcodebuild test -scheme Zmole -destination 'platform=macOS'`：108 tests，0 failures（含 `NavigationTests` 9 条）。
- 对照权威视觉 `docs/design/mole_desktop_demo_cn_final.html`（SHA-1 校验 = c63069df99bf58b3d9f946b17f7e8f78c30293eb）的 `.app-shell` / `.sidebar` / `.command-palette` / `data-page` 分组与 `:root` 颜色变量。
- 解析 `Localizable.xcstrings`：确认十目的地标题+副标题在 en / zh-Hans / zh-Hant 均存在，`app.name` 三语均 `zmole`，无键被删除。

AC 核对：AC-001（十目的地、双分组、选中态、启动概览）、AC-002（面板仅导航、无执行动作）、AC-003（`.appSettings` 替换为选中设置页）、AC-004（`WindowMetrics` 1100×700、`ShellChrome.drawsCustomTrafficLights=false`、系统标题栏）、AC-005（`app.name`=zmole）、AC-006（三语标签）均成立。旧 `AppMode`/`ContentView`/五模式 wrapper 及 `Settings` scene 已删净，无悬挂引用。

## Findings

### t015_gen_f001 - 命令面板底部提示「↑↓ 导航」无对应实现

- 严重度：minor
- 锚点：行为缺陷（AC-002 面板可用性）+ 失败场景：用户按 ↑/↓ 期望移动选中项，实际无反应，面板只支持回车打开首条、点击与 Esc 关闭。
- 位置：`src/zmole/App/CommandPaletteView.swift:53`（提示文案），`src/zmole/App/CommandPaletteView.swift:22,71`（仅有 `onSubmit` / `onExitCommand`）
- 问题：`palette.hint.navigate` 三语均显示「↑↓ 导航 / ↑↓ Navigate / ↑↓ 瀏覽」，但视图无 `.onMoveCommand` 或方向键处理，提示承诺了不存在的交互。
- 建议：要么实现方向键选中（配 `selectedIndex` 状态），要么去掉该提示项。spec 只要求「按名称过滤并打开」，删除提示即可闭合。

### t015_gen_f002 - AC-002/AC-003 的两条测试为自证式，无法证伪

- 严重度：minor
- 锚点：AC-002 / AC-003 + 测试可信度
- 位置：`tests/unit/NavigationTests.swift:33`、`:39-45`；`src/zmole/App/NavigationModel.swift:16,21`
- 问题：`isExecutionAction` 恒为 `false`、`forbiddenIdentifiers` 为硬编码集合，测试断言的是常量本身，与被测面板任何行为无关；`testSettingsCommandSelectsSidebarSettingsPage` 只调 `navigation.select(.settings)`，未触达 `ZmoleApp` 的 `.appSettings` 命令接线，即使命令缺失也会通过（假绿）。
- 建议：面板测试改为断言 `items.count == AppDestination.allCases.count` 且每行只有一个导航目的地；设置命令至少断言命令闭包逻辑抽出的函数/接线点（或在注释中显式声明该接线依赖手工黑盒覆盖）。

### t015_gen_f003 - 面板按名称过滤忽略应用内语言覆盖

- 严重度：minor
- 锚点：AC-002 + 失败场景：系统为英文、应用内切到中文时，输入「清理」得不到结果。
- 位置：`src/zmole/App/NavigationModel.swift:70-72`（`String(localized:)` 用进程 locale，非 `\.locale` 环境）
- 问题：`displayName(for:)` 以 `String(localized:)` 解析，无法读到 `AppShellView` 注入的 `\.locale`；过滤仅额外兜底 `rawValue`（英文）。中/繁名称过滤在系统 locale 与应用内语言不一致时失效。
- 建议：过滤词表用 `destination.titleKeyString` 对应的 `AppLanguage` 显式查表（或传入选定 locale），而非依赖进程 locale。

### t015_gen_f004 - 未同步受本 task 直接影响的文档（旧 IA/旧窗口尺寸）

- 严重度：minor
- 锚点：doc/config consistency（非 diff 内文件，但被本 task 事实推翻）
- 位置：`docs/blueprint/testing.md`（`## blackbox_verify` 仍写「进入 Software → Protection rules 并保存」「截图验收覆盖 1200×760 与 880×620」）；`docs/design/demo_launch.md:3`（仍称演示复用 `ContentView`）
- 问题：本 task 已把最小窗口改为 1100×700、并取消 Software/Protection rules 导航与 `ContentView`，上述门禁与参考文档未更新，按 testing.md 执行会走到已不存在的最小尺寸与入口。
- 建议：随本 task 收尾同步 `testing.md` 的 smoke 路径与尺寸、`demo_launch.md` 的入口描述（`ui_contract.md`/`architecture.md` 已正确更新）。

### t015_gen_f005 - 侧栏/分隔线颜色为近似值而非权威 CSS 变量

- 严重度：minor
- 锚点：spec「颜色…按 HTML 的 CSS 变量落到浅色与深色」
- 位置：`src/zmole/App/MoleTheme.swift:16`（`sidebar = 0xF0F0F2`）、`:20`（`line = 0xE6E6EA`）
- 问题：权威 HTML 的 `--sidebar` 为 `rgba(245,245,247,.82)` + `backdrop-filter:blur(22px)`，`--line` 为 `rgba(29,29,31,.09)`；实现改用不透明近似色，侧栏与浅色背景对比与基线略有差异（其余颜色变量与 `:root` 精确一致）。
- 建议：如需严格对齐，侧栏用材质/半透明或直接采用基线灰阶；否则接受近似并在注释说明偏差。

## 结论

- 本轮新发现：5 条（全部 minor）
- 未进表的提示：`Localizable.xcstrings` 保留未使用的旧键（`mode.software`、`sidebar.analyze`、`sidebar.whitelist` 等），无键删除，属清理范畴不影响功能；`MoleTheme.titlebarHeight=54` 已定义未使用，与后续 page task 相关，暂不阻断。
- 总体判断：实现与 spec 六个 AC 一致，编译与 108 条单测通过，删除的旧导航无悬挂引用，源码/工程/localization/docs 基本自洽。无 critical/important，未发现安全、契约或数据破坏风险。面板方向键提示为体验瑕疵，测试有两条偏弱，文档有局部滞后，均可在收尾或后续 task 处理。
- 系统性 follow-up：命令面板（t018/t016 相邻壳层工作）补方向键选中并统一过滤 locale 口径；收尾时同步 testing.md/demo_launch.md。

verdict: PASS

### Round 2 (2026-10-16T17:29:53+08:00)

复核 `git -C /Users/karson/kar/code/zmole_t015 diff 00814db3ebf3d6b288625cbbd167120f0b9205ce`（更新后内容）；`xcodebuild test` 108/108 通过。

#### 上轮 finding 处置

- `t015_gen_f001`（面板「↑↓ 导航」无实现）：**resolved（代码层）**。`CommandPaletteView` 新增 `selectedIndex`、`.onMoveCommand` up/down、选中行 `surface3` 高亮，`onSubmit` 改为打开 `clampedSelection`（`CommandPaletteView.swift:47-49,73-87,116-120`）；`onChange(of: commandQuery)` 重置选中。残留风险（不计入本轮 finding）：搜索框自动聚焦，方向键是否仍被 NSTextField 消费而绕过 `.onMoveCommand` 属运行时 GUI 行为，按约定不在本地判定。
- `t015_gen_f002`（测试自证式）：**resolved**。`testCommandPaletteOnlyContainsNavigationRows` 现断言 `items.count == AppDestination.allCases.count` 与 destination/id 集合相等（`NavigationTests.swift:39-50`），加入执行动作会破坏等值；`testSettingsCommandSelectsSidebarSettingsPage` 显式注释 `.appSettings` 接线由 demo/手工覆盖（`:33-41`），符合 spec 可测试性声明。
- `t015_gen_f003`（过滤忽略应用内 locale）：**resolved（代码层）**。`displayNames(for:)` 用 `String(localized:locale:)` 解析 en/zh-Hans/zh-Hant 三语并去重，`filteredPaletteItems` 匹配任一语言名或 rawValue（`NavigationModel.swift:66-72,42-49`）。
- `t015_gen_f004`（文档滞后）：**resolved**。`testing.md` blackbox 与 `demo_launch.md` 已改为十目的地 IA（`--demo-page disk`、设置 → 保护规则）、尺寸 1200×780 / 1100×700，并记录旧名别名。
- `t015_gen_f005`（颜色近似）：**resolved**。`line` = 自适应基色 `.opacity(0.10)`（≈ `rgba(29,29,31,.09)` / `rgba(255,255,255,.10)`），`sidebar` = 基色 `.opacity(0.82)`（≈ `rgba(245,245,247,.82)`）。

#### 新发现

### t015_gen_f006 - 跨语言过滤修复无回归测试

- 严重度：minor
- 锚点：AC-002 + 测试可信度（f003 修复的验证缺口）
- 位置：`tests/unit/NavigationTests.swift:52-72`（`testCommandPaletteFiltersByQueryAndPerformsNavigation` 仅查英文 `disk`）；`src/zmole/App/NavigationModel.swift:66-72`
- 问题：f003 的核心是中/繁名称在系统 locale 不一致时也能过滤，但新增测试只断言英文查询，`displayNames` 的三语解析（locale 参数是否真正命中 zh-Hans/zh-Hant 词条）无自动化覆盖，回归时不会红。
- 建议：补一条断言——`commandQuery = "清理"`（zh-Hans）与 `"磁碟"`（zh-Hant）时 `filteredPaletteItems` 含对应目的地。

#### 结论（Round 2）

- 上轮 5 条：全部 resolved（f001、f003 记代码层 resolved + 运行时残留说明）。
- 本轮新发现：1 条（minor）。
- 未进表的提示：`openFirstResult()` 名称已与「打开当前选中项」语义不符，纯命名问题；`MoleTheme.sidebar` 半透明后叠在同色 `background` 上近似不透明，与权威 HTML 的边框+blur 表现一致，非缺陷。
- 总体判断：上轮 minor 全部闭合，实现仍与六个 AC 一致，编译与 108 条单测通过；无 critical/important，无安全、契约或数据破坏风险。
- 系统性 follow-up：随命令面板后续 task 补跨语言过滤回归测试。

verdict: PASS

### Round 3 (2026-10-16T17:32:44+08:00)

复核 `git -C /Users/karson/kar/code/zmole_t015 diff 00814db3ebf3d6b288625cbbd167120f0b9205ce`：生产代码自 Round 2 起无改动（`CommandPaletteView.swift` 124 行、`NavigationModel.swift` 85 行与上轮一致），仅 `tests/unit/NavigationTests.swift` 新增一条测试（144 行）。`xcodebuild test -only-testing:ZmoleTests/NavigationTests` 10/10 通过。

#### 上轮 finding 处置

- `t015_gen_f006`（跨语言过滤无回归测试）：**resolved**。新增 `testCommandPaletteFiltersAcrossAllSupportedLanguages`（`NavigationTests.swift:118-128`）：断言 `displayNames(for: .clean)` 非空且含 `"清理"`，并以 `commandQuery = "清理"` 断言 `filteredPaletteItems` 含 clean。该断言有效——测试宿主确实解析字符串目录，若 zh-Hans 解析退化，`displayNames` 会回退为资源键 `sidebar.clean`，`contains("清理")` 将失败；本地已实测通过，测试非空跑。

#### 新发现

无。生产路径未变，新增测试未引入新风险。旁注（不构成 finding）：测试内注释称「目录不可用时回退资源键仍会走多语解析路径」，但该场景下 `contains("清理")` 会失败，注释措辞与断言略不符，仅注释问题。

#### 结论（Round 3）

- 上轮 1 条（f006）：resolved。
- 本轮新发现：0 条。
- 未进表的提示：无。
- 总体判断：Round 1/2 全部 minor 已闭合，跨语言过滤现有有效回归覆盖；实现与六个 AC 一致，109/109 单测通过，无 critical/important，无安全、契约或数据破坏风险。

reviewed_scope: cf43c13a00bd6ee8

verdict: PASS
