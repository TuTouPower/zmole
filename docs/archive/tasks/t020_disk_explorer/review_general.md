# Task review t020（reviewer_focus: 通用）

- task: t020（slug: disk_explorer，review_level: single）
- spec: `docs/tasks/t020_disk_explorer/spec.md`
- diff_anchor: `a6b20775333d4ce11d98401017e0638e32dd96ea`
- target: `git -C /Users/karson/kar/code/zmole_t020 diff a6b20775333d4ce11d98401017e0638e32dd96ea`（新测试文件 intent-to-add，非 `...HEAD`）
- round: 1
- reviewed_at: 2026-10-16T19:35:20+08:00

## 门禁复跑

- `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 152 passed，0 failures（含新增 7 例）。
- `pytest .repo_template/tests -q -m contract` → 147 passed，367 deselected。

## Findings

### t020_gen_f001 - 新增但未使用的 `import AppKit`

- 严重度: minor
- 锚点: 通用（架构/规范）
- 位置: `src/zmole/Features/Analyze/AnalyzeView.swift:1`
- 问题: 本次改动新增 `import AppKit`，但 `AnalyzeView` 内无任何 AppKit 符号（`NSWorkspace` 等都在 `LiveFileRevealer`/`UninstallMetadata.swift`）。属于本次改动引入的无用 import。
- 建议: 删除该行（`import SwiftUI` 足够）。

### t020_gen_f002 - `refreshCurrent` 保留过期展开缓存

- 严重度: minor
- 锚点: AC/范围（重新分析刷新当前根）
- 位置: `src/zmole/Features/Analyze/AnalyzeViewModel.swift:81-84`（对比 `openDirectory`/`open(path:)`/`goBack` 都清空 `expandedPaths`/`childrenByPath`）
- 问题: 刷新只重跑 `loadCurrentPath()`，不清 `expandedPaths`/`childrenByPath`。若刷新前展开了某目录，刷新后顶层被替换，但展开行仍显示旧的缓存子项（大小/条目可能已过期）；被删除的目录其缓存也残留内存。
- 建议: 刷新时同样清空展开状态，或对已展开目录重新 `load` 其子项后再展示，使“重新分析刷新当前根”覆盖展开层级。

### t020_gen_f003 - 二级及更深目录的展开控件无可见效果

- 严重度: minor
- 锚点: 通用（功能正确性/范围“展开子项”）
- 位置: `src/zmole/Features/Analyze/AnalyzeView.swift:96-103`（渲染）与 `:156-166`（任意 `isDirectory` 都渲染 disclosure）
- 问题: 列表只渲染 `depth: 0` 顶层条目及其一层子项（`entryRow(child, depth: 1)`）。但 `entryRow` 对任意目录都渲染展开按钮，点击 `depth: 1` 的目录会 `toggleExpanded`、把孙级写入 `childrenByPath` 并翻转箭头，然而没有任何视图渲染孙级——按钮视觉上“展开”但不出现子行（`grep` 确认 `children(of:)` 仅在顶层分支被读）。demo 的 `renderDiskTreeRows` 是任意深度递归。
- 建议: 要么按 demo 递归渲染任意深度的已展开目录，要么对不支持再展开的层级隐藏 disclosure 控件，避免误导性交互。

### t020_gen_f004 - 展开失败被永久缓存且无并发/重试保护

- 严重度: minor
- 锚点: 通用（健壮性）
- 位置: `src/zmole/Features/Analyze/AnalyzeViewModel.swift:124-138`
- 问题: (1) `try? await loader.load(...)` 失败时静默写入 `childrenByPath[path] = []`，随后 `guard childrenByPath[entry.path] == nil` 使折叠后重展永不重试，错误也不可见；(2) `toggleExpanded` 不置 `isLoading`，快速连点会通过 `== nil` 守卫发出多条重复 `analyze` 命令，且“先 insert 后 await”会让加载中折叠、加载完又写回缓存的竞态出现状态与数据不一致。
- 建议: 失败时删除该键（允许重试）并可选地回传错误；加入 in-flight/去重守卫（例如以独立 loading 集合或任务句柄）。

### t020_gen_f005 - AC-003 无自动断言，与可测试性声明不符

- 严重度: minor
- 锚点: AC-003 / 测试可信度
- 位置: `tests/unit/DiskExplorerTests.swift`（无面积图↔列表选择同步、搜索过滤断言）
- 问题: spec 可测试性声明“AC-001–AC-006：注入两层 analyze JSON 后自动断言”，但新增测试未覆盖 AC-003 的“面积图选中→列表选中同一 path”与“搜索只过滤当前层”（均为 `View` 内 `selectedPath`/`search` 状态）。该 AC 仅靠代码走查确认。
- 建议: 抽出可测的选择/过滤逻辑（如把 `selected.path` 同步与 `filtered` 计算下沉为纯函数或 ViewModel 属性）并补断言；或修正在 spec 中声明 AC-003 为人工/走查验证。

### t020_gen_f006 - AC-005 用源码子串扫描，属启发式且偏脆

- 严重度: minor
- 锚点: AC-005 / 测试可信度
- 位置: `tests/unit/DiskExplorerTests.swift:96-107`
- 问题: 该测试对 `AnalyzeView.swift` 全文小写后匹配 `["delete","trash","trashItem","removeItem","clean("]`。它只证明源文本不含这些子串：对改名/换 API 的删除动作会漏报（假阴性），对无害标识符或注释含这些词会误报（假阳性）；且只扫描 View 文件，未覆盖“磁盘页”可能挂在 ViewModel 上的控件。仅作兜底可接受，但不应被当作 AC-005 的强证据。
- 建议: 保留文本兜底的同时，优先以视图/VM 暴露的动作集合做行为断言（例如断言页面可见动作白名单不含删除/废纸篓）。

## AC 复验方式

- AC-001: re_verified — `testEnteringDirectoryAnalyzesThatPathOnly` 断言 argv 序列 `[["analyze","--json"],["analyze","--json","/Applications"]]` 且 entries 来自下钻夹具。
- AC-002: re_verified — `testAreaShareIsSizeOverCurrentLayerTotal` 断言 `AnalyzeArea.share`；`totalSize`/`SpaceMapLayout.tiles` 走查确认只用当前层 `entries`。
- AC-003: trust_prior — 无自动断言；走查 `mapTile` 设 `selectedPath`、`List(selection:)` 绑定 + `.tag(entry.path)`、`visibleEntries` 仅过滤 `entries`（见 f005）。
- AC-004: re_verified — `testNameSortReordersRowsWithoutChangingBytes` 断言名称序改变且字节集合不变。
- AC-005: re_verified（弱证据）— `testDiskPageHasNoDeleteControl` 文本兜底；无删除/废纸篓动作（见 f006）。
- AC-006: re_verified — `testRevealUsesEntryPath` 断言 reveal 使用叶子 path；目录走 `openDirectory` 而非删除。

coverage = re_verified / 6 = 5/6（AC-003 为 trust_prior）。

## 结论

- 本轮新发现: 6 条，全部 minor（f001 无用 import；f002 刷新保留过期展开；f003 深层展开控件无效果；f004 展开失败缓存+竞态；f005 AC-003 缺测；f006 AC-005 证据偏脆）。
- 未进表的提示:
    - 与视觉权威 `renderDisk` 的行为差异（非 AC 违规，记录备查）：demo 用搜索词同时过滤列表与方块图，本实现只过滤列表；demo 排序控件在文件工具条内且含“按类型”，spec 限定仅大小/名称，本实现符合 spec；demo 的“在 Finder 中显示”仅叶子项，本实现目录项也可 reveal（AC-006 只禁止删除，未禁止 reveal）。
    - `task.md` front matter 经 `task.py` 更新为 active 且 diff_anchor 正确，符合规范；`project.yml` 以 `tests/unit` 目录 glob 收测试，`pbxproj` 手改与该生成结果一致。
- 总体判断: 六条 AC 均满足且可复验（AC-003 走查通过），只读约束与无删除控件成立，纯函数拆分（`AnalyzeSort`/`AnalyzeListOrder`/`AnalyzeArea`）与注入式 `FileRevealing` 提升可测性，无安全/数据破坏风险。boundary 内“刷新过期展开”“深层展开控件”为体验级瑕疵，不阻塞。
- 系统性 follow-up: 建议为 f002/f003/f004 开一条 pending（磁盘页展开/刷新的状态一致性），为 f005 补 AC-003 的可测化重构。

verdict: PASS

### Round 2 (2026-10-16T19:37:45+08:00)

- reviewed_at: 2026-10-16T19:37:45+08:00
- target: `git -C /Users/karson/kar/code/zmole_t020 diff a6b20775333d4ce11d98401017e0638e32dd96ea`（同 anchor，未换 base）

#### 处置确认

|finding_id|severity|status|证据|
|---|---|---|---|
|t020_gen_f001|minor|已修|`AnalyzeView.swift:1` 现为 `import SwiftUI`，`import AppKit` 已删除|
|t020_gen_f002|minor|已修|`AnalyzeViewModel.swift:81-86` `refreshCurrent()` 现清空 `expandedPaths`/`childrenByPath` 后再 `loadCurrentPath()`|
|t020_gen_f005|minor|已修|新增 `testMapTilesCarryTheSamePathsAsCurrentLevelEntries`（`DiskExplorerTests.swift`），断言 `SpaceMapLayout.tiles` 的 `entry.path` 集合与当前层 `entries` 的 `path` 集合相等|
|t020_gen_f003|minor|遗留（降级接受）|一级展开视为满足“展开子项”，深层 disclosure 仍为无效交互；建议转 pending（`docs/pending/todo/pNNN_*.md`）|
|t020_gen_f004|minor|遗留（降级接受）|失败缓存与并发竞态仍存在，无 AC 影响；建议转 pending|
|t020_gen_f006|minor|遗留（降级接受）|AC-005 仍以源码子串扫描为兜底，证据偏脆；建议转 pending|

#### 新增/回归扫描

- 新增 finding: 0。
- f005 测试为结构性代理（tiles↔entries 路径等价），未覆盖 AC-003 的“搜索只过滤当前层”子句——搜索仍为走查，未见新缺陷。
- 逐 hunk 复核 `AnalyzeView.swift`/`AnalyzeViewModel.swift`/`DiskExplorerTests.swift` 与 `Localizable.xcstrings`：无回归，无新增越界改动；`children(of:)` 仍仅顶层分支消费（f003 保持现状，已知）。
- 门禁复跑: `xcodebuild test -scheme Zmole -destination 'platform=macOS'` → 153 passed，0 failures；`pytest .repo_template/tests -q -m contract` → 147 passed，367 deselected。

#### AC 复验方式（Round 2 更新）

- AC-001: re_verified — 同 Round 1。
- AC-002: re_verified — 同 Round 1。
- AC-003: re_verified（代理）— `testMapTilesCarryTheSamePathsAsCurrentLevelEntries` 证明方块图条目与当前层条目 path 等价，选择经同一 path 映射回列表；搜索子句仍走查。
- AC-004: re_verified — 同 Round 1。
- AC-005: re_verified（弱证据）— 同 Round 1。
- AC-006: re_verified — 同 Round 1。

coverage = re_verified / 6 = 6/6（AC-003 为结构性代理，搜索子句仍走查）。

#### 结论

- 本轮新发现: 0 条。
- 未进表的提示: f003/f004/f006 降级为可接受 minor，无 AC 影响，建议统一登记一条 pending 追踪；`docs/specs_index.md` 仍为空（t020 未收尾，正常）。
- 总体判断: Round 1 的 f001/f002/f005 均已闭环且经复跑验证，门禁 153/147 全绿，无回归；剩余三项 minor 不阻塞。

reviewed_scope: 8539e0d49daafe35

verdict: PASS
