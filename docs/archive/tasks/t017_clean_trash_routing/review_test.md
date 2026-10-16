# Task review t017（reviewer_focus: test）

- task：`t017_clean_trash_routing`
- spec：`docs/tasks/t017_clean_trash_routing/spec.md`
- diff_anchor：`0be6d3ef39d0e480ebff7e9a6e71d63cf2f51fb3`
- target：`git -C '/Users/karson/kar/code/zmole_t017' diff 0be6d3ef39d0e480ebff7e9a6e71d63cf2f51fb3`
- round：1
- reviewed_at：2026-10-16T18:33:00+08:00

## 验证事实

- `bash tests/integration/clean_trash_test.sh` → 8/8 通过（含同名前缀用例），退出 0。
- `pytest .repo_template/tests -q -m contract` → 147 passed, 367 deselected。
- 新测试文件为 intent-to-add，未被 gitignore（`git check-ignore` rc=1），mode 100755。
- 红绿归因：把生产库 `core/file_ops.sh`、`clean/user.sh` 还原为 diff_anchor 版本后重跑同一测试（临时副本，未改工作区）→ 6 条失败、2 条通过。逐条：

|用例|pre-patch 结果|是否红绿可信|
|---|---|---|
|AC-001 clean moves target into Trash|FAIL `not in Trash`|是|
|AC-002 failed Trash move keeps original and fails|FAIL `expected failure rc, got 0`|是|
|AC-003 existing Trash contents survive clean|**ok**|**否（假绿）**|
|AC-004 dry-run does not preview Trash emptying|FAIL `preview mentioned Trash`|是|
|AC-005 un-trashable target is not permanently deleted|FAIL `expected failure rc, got 0`|是|
|AC-005 privileged sink routes target into Trash|FAIL `expected success rc, got 11`|是|
|AC-005 privileged sink keeps original on failed Trash move|**ok**|否（但成功用例已红绿）|
|AC-001 duplicate basenames do not overwrite each other|FAIL `expected 3 trash entries, got 0`|是|

- 触及性核验：测试 `source` 的真实生产文件为 `MOLE_LIB/core/common.sh`（line 16-27 级联 `core/file_ops.sh`）与 `MOLE_LIB/clean/user.sh`；`safe_remove` / `safe_sudo_remove` / `clean_trash` 均为捆绑库定义，测试未 shadow（仅按需 override 一个分支判定函数）。插桩验证（临时副本）：`AC-005 privileged sink` 用例确实进入 `safe_sudo_remove` 新增 clean 分支，且未走 `safe_remove` 降级、未调用 `_mole_bounded_sudo`（即用无提权 `mv` 完成移动）。

## Findings

### t017_test_f001 - AC-003 用例未验证 AC-003，还原补丁后仍通过（假绿）

- 严重度：important
- 锚点：AC-003
- 位置：`tests/integration/clean_trash_test.sh:71-79`
- 问题：用例只对 `$HOME/Library/Caches/zmole_trash_check` 调用 `safe_remove`，随后断言预先放进 `~/.Trash` 的 `pre_existing.txt` 仍在。它**从不调用 `clean_trash`，也不跑真实 clean**——而"同一次 clean 不再清空 `~/.Trash`"的删除机制正是 `clean_trash`（`lib/clean/user.sh:36-40`）。因此断言与待测行为无关：把 anchor（未打补丁）生产代码还原后该用例仍 `ok`（对照上表），即无论补丁在不在、无论 `clean_trash` 是否被回退，它都通过。AC-003 实际上零信号覆盖。
- 建议：新增用例调用真实运行模式的 `clean_trash`（`DRY_RUN=false`）或走完整 clean 流程，断言预先存在的 Trash 项在 clean 结束后**原样仍在**（不只"存在"——若 `clean_trash` 上游体被回退，`safe_remove` 会把 Trash 项重命名为 `*.N.<ts>.<pid>`，用 `-e` 仍为真，需同时断言文件名未变）。

### t017_test_f002 - 提权移入废纸篓的实际代码路径（`sudo mv`）零覆盖

- 严重度：important
- 锚点：AC-005 / 测试覆盖
- 位置：`tests/integration/clean_trash_test.sh:120-150`；生产 `src/zmole/Resources/mole/lib/core/file_ops.sh:2052-2060`
- 问题：两个提权用例把目标放在 `$HOME/Library/Caches/**`（用户可写），`_mole_clean_trash_path` 的无提权 `mv` 即成功；唯一执行提权移动的 `_mole_bounded_sudo ... -n mv "$path" "$trash_destination"`（file_ops.sh:2053-2054，AC-005 字面要求"提权删除"的落点）**在任何用例中都未被执行**（插桩确认）。同时 `AC-005 privileged sink keeps original on failed Trash move` 在 anchor 版本下也通过（无 TTY 时 `sudo -n rm` 失败→文件保留），因此它并非该断言的可靠红绿。结论：提权路径对废纸篓的移动逻辑（及其失败不回退）没有被测试证伪能力。
- 建议：以 override 方式 stub `_mole_bounded_sudo`，让首个 `_mole_clean_trash_path` 失败（源目录不可写、废纸篓可写）以触达 `sudo mv` 分支：一例断言 stub 收到 `mv` 且原路径消失、无 `rm` 调用；一例让 stub 失败并断言原文件保留、返回非零。

### t017_test_f003 - AC-004 用例的 `record_dry_run_cleanup_target` stub 为死代码

- 严重度：minor
- 锚点：测试可信/危险模式
- 位置：`tests/integration/clean_trash_test.sh:88-90`
- 问题：`recorded` 计数器与 `record_dry_run_cleanup_target` stub 定义后从未断言（`recorded` 不被读取）；且该 stub 对结果无影响——上游 `clean_trash` 在 `if declare -f ...` 之后无条件 `preview_count++`，故断言本身（`grep -qi "Trash"`）不依赖 stub。真正有效的断言是 grep，且已验证红绿（见上表）。stub 与 `export -f ... 2>/dev/null || true` 属噪声，容易让读者误以为在验证记录行为。
- 建议：删除 stub/`recorded`，或改为有意义的断言（如 `recorded -eq 0`）。

### t017_test_f004 - 未覆盖补丁作用域：非 clean 命令仍应永久删除

- 严重度：minor
- 锚点：测试覆盖（spec 非范围：不改卸载/项目清理/优化的永久删除）
- 位置：`tests/integration/clean_trash_test.sh`（全文件，缺负向用例）
- 问题：全部用例都设 `MOLE_CURRENT_COMMAND=clean`。补丁以 `[[ "${MOLE_CURRENT_COMMAND:-}" == "clean" ]]` 为唯一守卫（file_ops.sh:1608、2045）；若该守卫被误删或改宽，卸载/优化/purge 会一起变成"移入废纸篓"，而现有套件仍全绿。spec 非范围明确要求这些路径保持永久删除。
- 建议：加一例 `MOLE_CURRENT_COMMAND=optimize`（或 unset），断言目标被真实删除且未出现在废纸篓。

## 结论

- 本轮新发现：4 条（important ×2，minor ×2）。
- AC 覆盖：
    - AC-001：可信。单例与同名不覆盖用例均红绿（`safe_remove` clean 分支落点）。
    - AC-002：可信。还原补丁后失败，且断言原文件保留、返回非零。
    - AC-003：不可信（f001）。用例不触达 `clean_trash` 实运行路径，anchor 版本下仍通过。
    - AC-004：可信。还原补丁后 dry-run 预览输出 `Trash · would empty` 使用例失败。
    - AC-005：部分。`safe_remove` 无提权失败/成功用例红绿；提权 sink 的 `sudo mv` 分支与失败不回退未被覆盖（f002）。
- 未进表的提示：
    - 失败类用例依赖 `chmod 500` 制造不可写；以 root 运行套件时 AC-002/AC-005 会假失败（预期非 root 环境，暂记）。
    - `run_case`（line 24）以 `set +e` 起子 shell，子体内未被显式检查的命令失败不会中止该用例，会掩盖中间错误——与 f001 的 AC-003 弱断言叠加时尤其明显。
    - `run_case` 的 `mktemp -d` 目录从不清理（列在 `TMPDIR` 之外仓库，属轻微卫生问题，不入表）。
    - 本地 shell 存在 `rm` 别名指向 `trash`，但测试以非交互 bash 运行、`register_rm` 未触发，对本套件无影响。
- 红绿归因：本轮未改动/删除任何既有测试；test 侧 diff 仅为新增 `tests/integration/clean_trash_test.sh` 与在 `testing.md` 的 `## test_cmd` 追加该命令。无归因问题。
- 总体判断：测试确实 source 生产捆绑库并调用真实 sink，大部分 AC 的红绿可信；但 AC-003 用例为假绿（还原补丁仍通过），且 AC-005 提权移篓的 `sudo mv` 分支无任何覆盖，故测试层不足以判定 AC-003/AC-005 满足。

verdict: FAIL

### Round 2 (2026-10-16T18:40:29+08:00)

- target：`git -C '/Users/karson/kar/code/zmole_t017' diff 0be6d3ef39d0e480ebff7e9a6e71d63cf2f51fb3`（`tests/integration/clean_trash_test.sh` 由 178 行增至 202 行，9 个用例）
- 门禁：`bash tests/integration/clean_trash_test.sh` → 9/9 通过（退出 0）；`pytest .repo_template/tests -q -m contract` → 147 passed。

#### 复证（红绿归因，均以生产库还原为 anchor 版本、临时副本执行，未改工作区）

|场景|结果|说明|
|---|---|---|
|全量还原 anchor（无补丁）|7 失败 / 2 通过|ACL-001/002/003/004、AC-005 un-trashable、AC-005 privileged success、同名不覆盖失败|
|仅还原 `clean/user.sh`（`file_ops.sh` 保留补丁）|AC-003、AC-004 失败|AC-003 现能区分 `clean_trash` 补丁|
|把两处 `MOLE_CURRENT_COMMAND == "clean"` 守卫去除（无条件入篓）|`non-clean commands still delete permanently` 失败|新增作用域用例能区分守卫|

#### Round 1 发现处置

- `t017_test_f001`（AC-003 假绿，important）→ **已修**。AC-003 用例现 source `clean/user.sh` 后以 `DRY_RUN=false` 调用真实 `clean_trash` 入口（line 74-85），断言既有 Trash 项仍在且 `rc==0`。复证：全量 anchor 下失败（输出 `clean emptied the Trash`），仅还原 `clean_trash` 时也失败。判别成立——还原后 `clean_trash` 上游体会经 `safe_remove` 把 `pre_existing.txt` 重命名为 `pre_existing.txt.1.<ts>.<pid>`，`-e` 断言因此不成立。位置：`tests/integration/clean_trash_test.sh:71-85`。
- `t017_test_f002`（提权 `sudo mv` 子路径零覆盖，important）→ **已修（含一处残余）**。新增两个用例（line 123-153）stub `_mole_privileged_path_has_mutable_ancestor`/`_mole_clean_trash_path`/`_mole_bounded_sudo`，成功例的 `_mole_bounded_sudo` stub 执行真 `mv`。sentinel 插桩确认该 stub 在成功例中确被调用；anchor 下成功例失败（`not in Trash`），判别成立。残余见新发现 f005。
- `t017_test_f003`（AC-004 死 stub，minor）→ **已修**。`record_dry_run_cleanup_target`/`recorded` 及 `export -f ...||true` 已移除；AC-004 只保留 `grep -qi "Trash"` 有效断言，且 anchor 下失败。
- `t017_test_f004`（缺非 clean 作用域负向用例，minor）→ **已修**。新增 `non-clean commands still delete permanently`（line 155-174），`MOLE_CURRENT_COMMAND=optimize`，断言目标被真实删除且未入篓。复证：去除 clean 守卫后该用例失败，判别成立。

#### 新发现

### t017_test_f005 - 提权用例 stub 掉 `_mole_clean_trash_path`，丢失"sudo 分支内先试无提权移动且成功"子路径覆盖

- 严重度：minor
- 锚点：测试覆盖 / AC-005
- 位置：`tests/integration/clean_trash_test.sh:125-138`；生产 `src/zmole/Resources/mole/lib/core/file_ops.sh:2047-2064`
- 问题：round 1 的提权用例曾覆盖"`safe_sudo_remove` clean 分支中以真实无提权 `mv` 成功"（`_mole_clean_trash_path` 返回 0 的分支）；round 2 把成功例的 `_mole_clean_trash_path` stub 成恒返回 1，改去覆盖 `sudo mv` 回落。结果：`safe_sudo_remove` 中 `trash_rc -eq 0` 的第一次尝试成功分支及其 `return 0`（file_ops.sh:2048-2064 前半）不再被任何用例执行。AC-001 覆盖的是 `safe_remove` 内同名函数的调用，不覆盖该处上下文。
- 建议：保留/追加一例不 stub `_mole_clean_trash_path` 的提权用例（仅 stub `_mole_privileged_path_has_mutable_ancestor`），断言目标经无提权 `mv` 入篓、`_mole_bounded_sudo` 未被调用。

#### 其余观察（未进表）

- 作用域用例以 `rm() { command rm "$@"; }`（line 163）走 `declare -F rm` 直删分支，绕开 `_mole_timeout_with_deadline`/`run_with_timeout` 定时路径；该用例目的仅为验证 `clean` 守卫，定时删除实现不在其判别范围，可接受。
- 提权成功例的 stub `_mole_bounded_sudo() { shift 2; "$@"; }` 硬编码"前两个参数为 timeout 与 `-n`"；属白盒耦合，若生产签名变更会静默改变被测命令，建议加一句注释或断言。
- `run_case`（line 24）仍以 `set +e` 起子 shell，子体内未被显式检查的命令失败不会中止用例；现各关键步骤均有显式断言，风险已大幅降低。
- 失败类用例仍依赖 `chmod 500` 制造不可写，root 下会假失败（环境前提，暂记）。

#### 结论（Round 2）

- 本轮新发现：1 条（minor）。
- AC 覆盖：AC-001/002/003/004 均红绿可信；AC-005 的 `safe_remove` 失败/成功与 `safe_sudo_remove` `sudo mv` 回落均已被有效用例覆盖，仅提权分支"先试无提权移动"子路径无覆盖（f005，低影响）。
- 红绿归因：未改动/删除既有测试，无归因问题。

verdict: PASS

### Round 3 (2026-10-16T18:44:52+08:00)

- target：`git -C '/Users/karson/kar/code/zmole_t017' diff 0be6d3ef39d0e480ebff7e9a6e71d63cf2f51fb3`（`tests/integration/clean_trash_test.sh` 由 202 行改为 189 行，8 个用例；生产 `file_ops.sh` 提权分支改为委托 `_mole_move_path_to_user_trash`）
- 门禁：`bash tests/integration/clean_trash_test.sh` → 8/8 通过（退出 0）；`pytest .repo_template/tests -q -m contract` → 147 passed。
- 生产改动核对：`safe_sudo_remove` 的 clean 分支（`file_ops.sh:2042-2062`）现调用上游既有 `_mole_move_path_to_user_trash`（`file_ops.sh:2617`，root staging relay + invoking-user 终移），不再调用 `_mole_clean_trash_path`，也不含 `_mole_bounded_sudo mv` 回落。

#### 复证（红绿归因，生产库还原为 anchor 后临时副本执行，未改工作区）

|用例|anchor 结果|判别|
|---|---|---|
|AC-001 clean moves target into Trash|FAIL|可信|
|AC-002 failed Trash move keeps original and fails|FAIL|可信|
|AC-003 running clean_trash keeps existing Trash contents|FAIL|可信|
|AC-004 dry-run does not preview Trash emptying|FAIL|可信|
|AC-005 un-trashable target is not permanently deleted|FAIL|可信|
|AC-005 privileged sink keeps original when Trash move is impossible|**ok**|**不可信（假绿）**|
|non-clean commands still delete permanently|ok|预期（守卫用例，见下）|
|AC-001 duplicate basenames do not overwrite each other|FAIL|可信|

- 全量 anchor：6 失败 / 2 通过。
- 作用域守卫判别：去除两处 `MOLE_CURRENT_COMMAND == "clean"` 后 `non-clean commands still delete permanently` 失败，判别成立（该用例在 anchor 下通过属预期）。
- 提权分支走向核对（sentinel 插桩）：post-patch 下 `_mole_move_path_to_user_trash` 被调用；anchor 下不被调用（改走 `_mole_bounded_sudo … rm`）。以此可构造可信断言，见 f006。

#### Round 1 / Round 2 发现处置

- `t017_test_f001`（AC-003 假绿，important）→ **保持已修**。anchor 下 AC-003 仍失败（`clean emptied the Trash`），判别成立。
- `t017_test_f002`（提权 `sudo mv` 子路径零覆盖，important）→ **保持已修**。anchor 下 AC-005 `un-trashable` 用例失败。
- `t017_test_f003`（AC-004 死 stub，minor）→ **保持已修**。
- `t017_test_f004`（非 clean 作用域负向用例，minor）→ **保持已修**（守卫去除后失败）。
- `t017_test_f005`（提权用例 stub `_mole_clean_trash_path` 丢失首试子路径，minor）→ **已消除（因生产重构而失效）**。提权分支已不再调用 `_mole_clean_trash_path`，该子路径不存在；改为委托 `_mole_move_path_to_user_trash`。f005 描述的覆盖缺口随代码变更消失，但其背后的"提权路径无判别性覆盖"问题在 round 3 以新形式回归，见 f006。

#### 新发现

### t017_test_f006 - 提权 AC-005 用例假绿：anchor 下同样通过，删除合成成功例后提权路径再无判别性覆盖

- 严重度：important
- 锚点：AC-005 / 测试可信（假绿）
- 位置：`tests/integration/clean_trash_test.sh:126-140`；生产 `src/zmole/Resources/mole/lib/core/file_ops.sh:2042-2062`
- 问题：该用例仅断言 `safe_sudo_remove` 返回非零且原文件保留。无 passwordless sudo 时，未打补丁的 anchor 也在 `_mole_bounded_sudo -n rm -rf` 处失败、文件保留，因此**全量还原 anchor 后该用例仍通过**（本轮复证：6 失败中不含此例）。删除 round 2 的合成成功例后，提权 sink 再无任何能区分补丁是否存在的用例；AC-005 字面的"提权删除"分支实际零判别覆盖。sentinel 插桩证明：post-patch 会调用 `_mole_move_path_to_user_trash`，anchor 则不会——差异真实存在但未被断言捕获。
- 建议：把提权用例改为判别式断言：stub `_mole_move_path_to_user_trash() { : > "$HOME/.trash_relay_called"; return 1; }`，断言该哨兵文件存在（证明路由到 user-trash 中继而非 `rm`）且原文件保留、返回非零。这样 anchor 下哨兵缺失即失败，得到红绿。

#### 其余观察（未进表）

- 提权用例依赖环境中 `sudo -n` 失败作为"无法入篓"前提。若宿主有 NOPASSWD sudo，则该被测分支会**成功**（rc=0）而使用例假失败，且副作用是真实创建 root 属主 `/Library/MoleTrashStaging` 并移动沙箱文件。标准 dev/CI 无 passwordless sudo，暂记；建议用例显式 stub `_mole_create_privileged_trash_stage`（返回 1）以自足表达"无法入篓"，同时彻底避免触达宿主 `/Library`。
- 提权用例 stub `_mole_valid_invoking_home`→沙箱 `$HOME`、`get_invoking_uid/gid`→当前用户，确保 `~/.Trash` 指向沙箱。已核对 `_mole_move_path_to_user_trash` 的 `trash_dir="${user_home%/}/.Trash"`，不会触碰开发者真实废纸篓。
- `run_case`（line 24）`set +e` 及 root 下 `chmod 500` 依赖等既有观察沿用 round 2，未变化。

#### 结论（Round 3）

- 本轮新发现：1 条（important）。
- AC 覆盖：AC-001/002/003/004 红绿可信；AC-005 的 `safe_remove` 失败路径可信，但**提权分支（AC-005 字面要求）因删去合成成功例后无判别性覆盖，仅存假绿用例**（f006）。
- 红绿归因：未改动/删除既有测试，无归因问题。
- 总体判断：非提权路径覆盖扎实且可信；提权路径的失败用例在无 sudo 环境下与未打补丁不可区分，AC-005 提权部分不足以判定满足。建议按 f006 补一条哨兵断言即可转绿。

verdict: FAIL

### Round 4 (2026-10-16T18:46:38+08:00)

- target：`git -C '/Users/karson/kar/code/zmole_t017' diff 0be6d3ef39d0e480ebff7e9a6e71d63cf2f51fb3`
- 门禁：`bash tests/integration/clean_trash_test.sh` → 8/8 通过（退出 0）；`pytest .repo_template/tests -q -m contract` → 147 passed。

#### 复证（全量还原 anchor 后临时副本执行）

- 全量 anchor：7 失败 / 1 通过。逐例：AC-001、AC-002、AC-003、AC-004、AC-005 un-trashable、AC-005 privileged（`privileged path did not delegate to the Trash helper`）、AC-001 duplicate basenames 均失败；仅 `non-clean commands still delete permanently` 通过（守卫用例，预期，round 2/3 已证其判别守卫去除）。

#### f006 处置

- `t017_test_f006`（提权 AC-005 假绿，important）→ **已修，判别成立**。用例（`tests/integration/clean_trash_test.sh:123-138`）现 stub `_mole_move_path_to_user_trash() { printf "called\n" > "$HOME/used_helper"; return 1; }`，随后依次断言 (a) `$HOME/used_helper` 存在、(b) `rc != 0`、(c) 原文件保留。anchor 不调用该 helper，故 anchor 下首条断言即失败（本轮实测：`privileged path did not delegate to the Trash helper`），post-patch 通过——由假绿转为红绿。仅当生产 `safe_sudo_remove` 的 clean 分支实际委托到 user-trash 中继时才写 marker，断言可信。
- 附带收益：该 stub 使提权用例不再触达 `_mole_create_privileged_trash_stage`（硬编码 `/Library/MoleTrashStaging` + `sudo -n`），round 3 记录的"宿主 NOPASSWD sudo 下会误失败并写宿主 `/Library`"风险随之消除；用例对宿主无副作用，也不再依赖 `sudo -n` 失败这一环境前提。

#### 其余发现

- 无新增。

#### 结论（Round 4）

- 本轮新发现：0 条。
- AC 覆盖：AC-001/002/003/004 红绿可信；AC-005 的 `safe_remove` 失败路径与提权 sink 委托路径均已红绿可信。round 1–3 全部发现（f001–f006）均已闭环，无回归。
- 红绿归因：未改动/删除既有测试，无归因问题。
- 总体判断：8 例集成测试均 source 真实生产库并对补丁有判别力；anchor 下 7/8 失败、post-patch 全绿，覆盖与可信度满足验收。

reviewed_scope: 99868a61c555c686

verdict: PASS
