# Task review t017（reviewer_focus: code）

- task：`t017_clean_trash_routing`
- spec：`docs/tasks/t017_clean_trash_routing/spec.md`
- diff_anchor：`0be6d3ef39d0e480ebff7e9a6e71d63cf2f51fb3`
- target：`git -C '/Users/karson/kar/code/zmole_t017' diff 0be6d3ef39d0e480ebff7e9a6e71d63cf2f51fb3`
- round：1
- reviewed_at：2026-10-16T18:33:00+08:00

门禁复核：`bash tests/integration/clean_trash_test.sh` → 8/8 通过；`pytest .repo_template/tests -q -m contract` → 147 passed。AC-001..005 实现层均有对应分支。

## Findings

### t017_code_f001 - 提权删除把 root `mv` 直接写进用户可控 `~/.Trash`，绕开仓库既有的 Trash 安全不变式

- 严重度：important
- 锚点：AC-005 + 安全不变式回归（提权目标入篓路径）
- 位置：`src/zmole/Resources/mole/lib/core/file_ops.sh:2053`
- 问题：新增的 sudo 分支用 `_mole_bounded_sudo ... -n mv "$path" "$trash_destination"` 让 root 直接 move 进 `$HOME/.Trash`。仓库已有一个 `_mole_move_path_to_user_trash`（`:2621`）专为“提权路径入废纸篓”设计，且在同一文件 `:2735` 明确写下不变式：“Never point a root mv directly into ~/.Trash”，并用 root 中继暂存目录 + 以 invoking user 身份完成最终 move 来规避 `~/.Trash` 被替换/符号链接劫持。本补丁既未复用该 helper（重复实现，DRY），也未做等价防护：`_mole_clean_trash_destination`（`:1262`）只做 `mkdir -p`，不检查 `trash_dir` 是否为 symlink、不校验属主。窗口内 `~/.Trash` 被替换为 symlink 时，root 会跟随链接把目标 move 到任意位置。适用于 `safe_sudo_remove` 的所有 clean 提权目标（如 `clean/system.sh` 的 macOS installer、系统缓存）。
- 建议：`safe_sudo_remove` 的 clean 分支改为委托 `_mole_move_path_to_user_trash "$path" true`（并沿用其返回码/取消语义），或至少补齐 `trash_dir` 非 symlink、属主校验与 root 暂存中继。

### t017_code_f002 - 废纸篓落点判定用 `-e` 判存在，悬挂符号链接目标无法入篓而残留

- 严重度：minor
- 锚点：行为缺陷 + 边界（符号链接目标）
- 位置：`src/zmole/Resources/mole/lib/core/file_ops.sh:1266`
- 问题：`_mole_clean_trash_destination` 以 `[[ -e "$path" ]] || return 1` 作为前置存在性判定，`-e` 会跟随链接，故指向已不存在目标的悬挂符号链接恒判为“不存在”，`_mole_clean_trash_path` 直接失败返回 1，该链接被保留。`validate_path_for_deletion`（`:1003`）允许合法符号链接作为删除目标，既有 helper 用 `[[ ! -e "$path" && ! -L "$path" ]]`（`:2635`）也接受链接；改动前 `rm -rf` 能移除悬挂链接，改后留下残留且被记为失败。
- 建议：存在性判定改为 `[[ -e "$path" || -L "$path" ]] || return 1`，与既有 helper 对齐。

### t017_code_f003 - sudo 入篓路径把超时/中断码一律降级为 1，丢失取消传播

- 严重度：minor
- 锚点：行为缺陷 + 取消/超时语义
- 位置：`src/zmole/Resources/mole/lib/core/file_ops.sh:2053`
- 问题：`_mole_bounded_sudo ... mv` 失败时被写成 `trash_rc=1`，随后返回 1。同一函数下方 rm 路径对 124（超时）与 `>=128`（中断）分别调用 `_mole_record_clean_cancellation` 并原样返回。清理由此在 Trash move 超时/被 Ctrl-C 时不再上报取消，clean 的取消/超时聚合（`MOLE_CLEAN_CANCEL_STATUS`、`MOLE_CLEAN_REMOVAL_TIMEOUTS`）统计会漏计。
- 建议：捕获 `_mole_bounded_sudo` 实际返回码，对 124/`>=128` 走与 rm 路径相同的 `_mole_record_clean_cancellation` 分支再返回。

### t017_code_f004 - `clean_trash` 直接返回后保留大段不可达函数体

- 严重度：minor
- 锚点：死代码 / 文件规模
- 位置：`src/zmole/Resources/mole/lib/clean/user.sh:41`
- 问题：`clean_trash` 现在 `return 0` 之后仍保留整段上游实现（约 100 行），成为不可达死代码。注释说明是“留作升级重放参考”，但这会让后续上游升级 diff 更易误读，且 shellcheck 会对不可达命令报 SC2317。属实现引入的死代码（非仓库既有）。
- 建议：若坚持保留，改为注释块或提取到独立 `.upstream-reference` 片段；否则整体删除，重放依据记入 `decisions.md`（已有 t017 补丁说明）。

### t017_code_f005 - `_mole_clean_trash_destination` 头部注释描述的是 `_mole_clean_trash_path` 的返回语义

- 严重度：minor
- 锚点：命名/文档准确性
- 位置：`src/zmole/Resources/mole/lib/core/file_ops.sh:1257`
- 问题：注释写“Returns 0 only when the target no longer exists at its original path and now lives under the Trash directory”，但该函数只 `printf` 目标路径、不 move，返回 0 仅表示“算出可用落点”。真正的 0/1 语义在 `_mole_clean_trash_path`（`:1284`）。注释错位会误导后续维护者判断失败语义。
- 建议：把该段注释移到 `_mole_clean_trash_path`，`_mole_clean_trash_destination` 只描述“解析并去重后输出废纸篓落点”。

### t017_code_f006 - `domain.md` 状态词条改动与 t017 无关，且反转既有表述

- 严重度：minor
- 锚点：范围
- 位置：`docs/blueprint/domain.md:16`
- 问题：diff 把 `|状态|status|只读健康快照（非 live watch）|` 改成 `...由 status --watch 实时采样`。t017 是清理删除改道，状态采样能力不在本 task 范围，且该改动反转了原词条的“非 live watch”结论，属于“精准修改”原则之外的顺带改动。
- 建议：若确需修正，单开文档变更或并入对应 status 任务；本 task 回退该行。

## 结论

- 本轮新发现：6 条（important 1、minor 5）
- 未进表的提示（文件过大/复杂度/范围外）：
    - `src/zmole/Resources/mole/lib/core/file_ops.sh` 已达 3775 行，`safe_remove`/`safe_sudo_remove` 均超长且分支密集；本 task 继续在其上叠加分支，进一步抬高复杂度，建议后续 task 拆分删除/入篓 sink。
    - `MOLE_TRASH_DIR` 为补丁新引入的测试可注入变量，未在 blueprint 记录；非阻塞。
- 总体判断：AC-001..005 均有实现落点，门禁 8/8 与 147 contract 全绿，无阻断性行为缺陷。主要风险在提权入篓路径绕开仓库既有 Trash 安全不变式（f001），其余为边界/语义精度问题。当前实现可合并，但 f001 建议在合并前或紧接的 follow-up 处理。
- 系统性 follow-up：提取统一的“入废纸篓 sink”（复用 `_mole_move_path_to_user_trash`），让 clean 与 uninstall 走同一套 symlink/属主/暂存防护，消除本 diff 的逻辑重复与不变式分叉。

verdict: PASS

______________________________________________________________________

## Round 2 (2026-10-16T18:38:53+08:00)

### 复核基线

- production diff（`src/zmole/Resources/mole/lib/core/file_ops.sh`、`src/zmole/Resources/mole/lib/clean/user.sh`）与 round 1 逐字节相同：三个 hunk `@@ -1254,6 +1254,43 @@`、`@@ -1565,6 +1602,21 @@`、`@@ -1985,6 +2037,37 @@` 位置与内容均未变。
- 描述中的 (a) 碰撞命名循环、(b) clean 分支位于 `expected_parent` 身份复检之后且成功 `sudo mv` 显式置 `trash_rc=0`，**在 round 1 的 diff 中即已存在**，本轮未见 production 变更。测试文件确有改动（新增 `non-clean commands still delete permanently`，9/9）。
- 门禁复核：`bash tests/integration/clean_trash_test.sh` → 9/9；`pytest .repo_template/tests -q -m contract` → 147 passed。

### 既有 finding 处置

- t017_code_f001（important，sudo `mv` 直写用户可控 `~/.Trash`，绕开 `_mole_move_path_to_user_trash` 的 symlink/属主/暂存不变式）：**未处置**。`_mole_clean_trash_destination` 仍只 `mkdir -p`，`safe_sudo_remove` 仍对 `~/.Trash` 直接 root `mv`；补丁未复用既有 helper。结论维持。
- t017_code_f002（minor，`-e` 判定漏 `-L`，悬挂链接无法入篓）：**未处置**，`:1266` 原样。
- t017_code_f003（minor，sudo 入篓把 124/`>=128` 降级为 1，丢失取消传播）：**未处置**，`:2053` 原样。
- t017_code_f004（minor，`clean_trash` 早返回后大段不可达）：**未处置**，`user.sh:41` 原样。
- t017_code_f005（minor，`_mole_clean_trash_destination` 头注错位）：**未处置**，`:1257` 原样。
- t017_code_f006（minor，`domain.md:16` 状态词条越界改动）：**未处置**，原样。

### 分支放置/逻辑回归扫描

- 放置：`safe_sudo_remove` clean 分支位于 `expected_parent` 身份复检（`:2034`）之后，源路径身份在 move 前已校验，与 rm 路径同窗口，无回归。
- 逻辑：`_mole_clean_trash_path` 先以当前用户尝试入篓，失败再走 sudo `mv`，语义与 round 1 一致；成功 `sudo mv` 后 `[[ -e "$path" ]] && trash_rc=1` 兜底正常。
- 冗余：分支内的 `"${MOLE_DRY_RUN:-0}" != "1"` 为冗余守卫（dry-run 已在本函数更早处返回），无害，非阻塞。
- 未发现新增行为缺陷或回归。

### 本轮结论

- 本轮新发现：0 条。
- 未进表的提示：与 round 1 相同（`file_ops.sh` 已 3775 行、`MOLE_TRASH_DIR` 未入 blueprint）。
- 总体判断：production diff 未变、门禁全绿、无回归，round 1 的 6 条 finding 全部仍未处置。f001 维持在合并前或紧接 follow-up 处理为宜；其余为精度问题。

verdict: PASS

______________________________________________________________________

## Round 3 (2026-10-16T18:43:35+08:00)

### 复核基线

- production 变更集中在 `src/zmole/Resources/mole/lib/core/file_ops.sh`：`_mole_clean_trash_destination` 存在性判定加 `-L`；`safe_sudo_remove` clean 分支改为委托 `_mole_move_path_to_user_trash "$path" true "$expected_parent" "$expected_parent_id" "$expected_target_id"`，并按 124/`>=128` 传播取消。
- `docs/blueprint/domain.md` 状态词条改动已回退（`（非 live watch）` 恢复），f006 处理。
- 门禁复核：`bash tests/integration/clean_trash_test.sh` → 8/8；`pytest .repo_template/tests -q -m contract` → 147 passed。

### 既有 finding 处置

- t017_code_f001（important，提权路径绕开 Trash 安全 helper）：**已处置**。分支不再直接 root `mv` 进 `~/.Trash`，改走既有 `_mole_move_path_to_user_trash`（root 暂存中继 + invoking-user 最终 move，含 symlink/属主/跨卷防护），并把 `expected_parent` 身份三元组透传，move 前多一次身份复检。签名/实参匹配（`path, needs_sudo, expected_parent, expected_parent_id, expected_target_id`）正确。结论：解决。
- t017_code_f002（minor，`-e` 漏悬挂链接）：**已处置**。`:1266` 改为 `[[ -e "$path" || -L "$path" ]]`；`_mole_clean_trash_path` 移动悬挂链接后 `[[ -e "$path" ]]` 为假，返回 0，无假失败。解决。
- t017_code_f003（minor，超时/中断丢失）：**已处置**。委托分支对 `trash_rc -eq 124 || -ge 128` 调 `_mole_record_clean_cancellation` 并原样返回，与 rm 路径一致。解决。
- t017_code_f004（minor，`clean_trash` 不可达体）：**按实现侧说明有意保留**，本轮不计未决缺陷；建议后续升级重放时清理（或改注释块），仅记录。
- t017_code_f005（minor，头注错位）：**已处置**。共享注释块现明确 `_mole_clean_trash_destination` 负责解析去重、`_mole_clean_trash_path` 负责实际 move 并承载返回 0/1 语义，歧义消除。解决。
- t017_code_f006（minor，越界 doc 改动）：**已处置**。`domain.md:16` 状态词条回退。解决。

### 分支放置/逻辑回归扫描

- 放置：clean 分支位于 `safe_sudo_remove` 的 `expected_parent` 身份复检（`:2034`）之后，且把同一身份透传给 helper 做二次复检，无 TOCTOU 扩大，比 rm 路径更严。无回归。
- 委托语义：`_mole_move_path_to_user_trash` 成功返回 0 且源不存在 → `TRASHED`+返回 0；返回 `MOLE_ERR_MUTABLE_PARENT`/`MOLE_ERR_PRIVACY_DENIED`/1 → `FAILED`+返回 1（AC-005 满足）；124/`>=128` 传播取消。`MOLE_TEST_MODE`/`MOLE_TEST_NO_AUTH` 下 helper 返回 1 → 失败保文件，fails closed，符合“不退回永久删除”。
- 函数定义顺序：`_mole_move_path_to_user_trash` 位于 `safe_sudo_remove` 之后，运行期全量 source 后调用，无未定义风险。
- 未发现新增行为缺陷或回归。

### 本轮 finding

### t017_code_f007 - 原 `# Safe wrapper around rm -rf with validation` 注释因插入新函数而悬空

- 严重度：minor
- 锚点：文档准确性（注释归属）
- 位置：`src/zmole/Resources/mole/lib/core/file_ops.sh:1256`
- 问题：原注释紧贴 `safe_remove()` 描述其职责；补丁在注释与 `safe_remove` 之间插入了两个新函数，该行现悬在 `_mole_clean_trash_destination` 之上，易被读成描述新 helper。
- 建议：把该行移回 `safe_remove` 定义前，或并入 t017 注释块。

### 本轮结论

- 本轮新发现：1 条（minor 1，f007）；f001–f003、f005、f006 已解决，f004 按实现侧说明有意保留。
- 未进表的提示（范围外/非阻塞）：
    - 集成测试不再覆盖提权入篓“成功入篓”路径（sandbox 无 sudo，helper 在 `MOLE_TEST_MODE`/`MOLE_TEST_NO_AUTH` 下恒返回 1），当前只验证失败保文件；AC-005 契约仅要求失败语义，非阻塞，留给 test reviewer 判断。
    - 委托分支内 `"${MOLE_DRY_RUN:-0}" != "1"` 仍为冗余守卫（dry-run 已在本函数更早返回），无害。
    - `file_ops.sh` 已 3775 行、`MOLE_TRASH_DIR` 未入 blueprint，同前。
- 总体判断：f001 安全不变式已通过复用既有 helper 修复，f002/f003/f005/f006 均已闭合，门禁全绿，无行为回归。仅剩 f004（有意保留）与新增 f007（注释归属）两条 minor。
- 系统性 follow-up：无新增；维持“统一入废纸篓 sink”方向，本轮已朝该方向收敛（提权路径已复用 `_mole_move_path_to_user_trash`）。

verdict: PASS

______________________________________________________________________

## Round 4 (2026-10-16T18:46:31+08:00)

### 复核基线

- production 唯一变更：`src/zmole/Resources/mole/lib/core/file_ops.sh` 中 `# Safe wrapper around rm -rf with validation` 注释移回 `safe_remove()` 正上方，t017 helper 注释块前移。新 hunk `@@ -1253,6 +1253,45 @@`；另两处 `safe_remove`/`safe_sudo_remove` hunk 内容未变（`@@ -1565,6 +1604,21 @@`、`@@ -1985,6 +2039,31 @@`），无逻辑变化。
- 门禁复核：`bash tests/integration/clean_trash_test.sh` → 8/8；`pytest .repo_template/tests -q -m contract` → 147 passed。

### 既有 finding 处置

- t017_code_f007（minor，注释悬空）：**已处置**。`:1256` 原注释回到 `safe_remove()` 前，t017 块独立前置，归属清晰。解决。
- t017_code_f001 / f002 / f003 / f005 / f006：round 3 已解决，本轮未见回退。
- t017_code_f004（minor）：实现侧有意保留，维持记录不计未决缺陷。

### 回归扫描

- 仅注释移动，无控制流、返回码、调用点变化；`safe_remove`/`safe_sudo_remove` 两个 sink 分支与 round 3 一致。
- 未发现新增行为缺陷或回归。

### 本轮结论

- 本轮新发现：0 条。
- 未进表的提示：与 round 3 相同（提权入篓成功路径非测试覆盖、冗余 `MOLE_DRY_RUN` 守卫、`file_ops.sh` 3775 行、`MOLE_TRASH_DIR` 未入 blueprint）。
- 总体判断：round 1 全部 finding 除有意保留的 f004 外已闭合，门禁全绿，无回归。

reviewed_scope: 99868a61c555c686

verdict: PASS
