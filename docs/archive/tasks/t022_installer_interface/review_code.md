# Task review t022（reviewer_focus: 代码）

- task：`t022_installer_interface`
- spec：`docs/tasks/t022_installer_interface/spec.md`
- diff_anchor：`770ea9aa58d07d4dbc1930669bdf7cdf520c0544`
- target：`git -C '/Users/karson/kar/code/zmole_t022' diff 770ea9aa58d07d4dbc1930669bdf7cdf520c0544`
- round：1
- reviewed_at：2026-10-16T20:05:57+08:00

## 方法与证据

- 落点：本会话 shell cwd 为主仓 `/Users/karson/kar/code/zmole`；评审对象为登记 worktree `/Users/karson/kar/code/zmole_t022`，全部 git/文件操作以 `git -C` 指向该 worktree 的 `t022_installer_interface` 分支。
- 阅读范围：`installer.sh` 全量 diff 与周边上下文，`tests/integration/installer_interface_test.sh`，`docs/blueprint/{architecture,decisions,domain,testing}.md`，以及被调用的 `lib/core/common.sh`(`mole_path_identity`)、`lib/core/base.sh`(`get_file_size`)、`lib/core/file_ops.sh`(`mole_delete`/`_mole_move_to_trash`)。
- 门禁实跑：`bash tests/integration/installer_interface_test.sh` → 10 pass/0；`bash tests/integration/clean_trash_test.sh` → pass；`pytest .repo_template/tests -q -m contract` → 147 passed。
- 运行环境：脚本 shebang `#!/bin/bash`，实际 macOS `/bin/bash` = 3.2.57（`/opt/homebrew/bin/bash` 不存在），`mo` 路由以 `exec "$SCRIPT_DIR/bin/installer.sh"` 落此 shebang，故 3.2 为生产运行时。
- 独立复现（构造夹具，非测试内）：空扫描 root 的 `--list-json`/`--remove`；列后改写大小再删除。见 f001/f002。

## Findings

### t022_code_f001 - 空候选扫描下 `--list-json` 输出为空（非 `[]`）、`--remove` 假成功，`set -u` 致命错误被 EXIT trap 吞成 rc=0

- 严重度：important
- 锚点：行为缺陷 —— 无任何候选时，非交互接口既不产出 JSON 也不拒绝，返回 0；违反列出接口「输出每个候选项」与「删除只接受列出的路径、不一致跳过并记失败」的契约前提。
- 位置：`src/zmole/Resources/mole/bin/installer.sh:848`（`for file in "${all_files[@]}"`），回退在 `:862-865`。
- 问题：`collect_installers_noninteractive` 先 `local -a all_files=()`，随后无条件 `for file in "${all_files[@]}"`。在 bash 3.2 + `set -u` 下，空数组的 `"${arr[@]}"` 展开触发致命 `unbound variable`，整个 shell 立即中止，`||` 回退不可达：
    - 复现 A（空扫描）：`MOLE_INSTALLER_SCAN_ROOT=<空目录> bash .../installer.sh --list-json` → stdout 为空（**不是** `[]`），stderr 打印 `line 836: all_files[@]: unbound variable`，`RC=0`。
    - 复现 B（空扫描 + remove）：`... --remove /tmp/notinstaller.txt` → stdout 空，`RC=0`，目标文件仍在。GUI 会据 rc=0 判为删除成功，属假成功。
    - `:862` 的 `printf '[]\n'` 回退在此路径不可达，说明实现者本意要处理空结果，但未生效。
    - rc=0 的机理：`set -u` 致命错误本应 non-zero，但脚本 `trap cleanup EXIT`，`cleanup` 末尾 `cleanup_temp_files` 返回 0，将退出码掩盖为 0。
    - 触发条件常见：生产不设 `MOLE_INSTALLER_SCAN_ROOT`，用户机器无安装包即空集合。门禁夹具恒含 `app.dmg`，不覆盖空夹具，故 10 pass 未捕获。
- 建议：`collect_installers_noninteractive` 用计数守卫后再展开，例如 `if [[ ${#all_files[@]} -gt 0 ]]; then for file in "${all_files[@]}"; do ... done; fi`；为 `--list-json` 空结果、`--remove` 空扫描各补一条集成用例（空扫描应输出 `[]` 且 remove 应 rc≠0）。

### t022_code_f002 - `--size` / `--identity` 缺省时退化为「与当前值比较」，AC-004 的「列出时不同则不删除」被绕过

- 严重度：important
- 锚点：AC-004 —— 大小/身份与列出时不同应不删除；实测列出后被改大小的文件在省略 `--size` 时仍被删除。
- 位置：`src/zmole/Resources/mole/bin/installer.sh:906`（`planned_size="${expected_size:-${INSTALLER_SIZES[$idx]}}"`）、`:911`（`planned_identity="${expected_identity:-$(mole_path_identity "$target")}"`）。
- 问题：两个「列出时值」在调用方省略时回退到**删除时**的值——`--size` 回退到 `collect_installers_noninteractive` 刚重扫的 `${INSTALLER_SIZES[$idx]}`，`--identity` 回退到当前 `mole_path_identity`。二者与 `:914/:922` 读取的当前值恒等，校验形同空操作。
    - 复现：list 时 `app.dmg` = 0 字节，identity=`inode:...`；随后写入 1234 字节；`--remove <path> --identity <listed>`（不传 `--size`）→ `RC=0`，原文件消失、出现在测试废纸篓。即「列出后被改写大小」的文件被删除，与 spec 测试策略点名的场景直接冲突。
    - 根因：接口不持久化 listing，也不强制调用方回传二者；「只接受本次列出的路径」实际退化为「出现在删除时重扫集合」。f002 与 TEST reviewer 的 `t022_test_f001`（覆盖缺口）互为两面：实现侧给了不安全缺省，测试侧未建对照故未拦。
- 建议：将 `--size` 与 `--identity` 视为必填；任一缺失即拒绝（`return 1`），不再回退到当前/重扫值。这样 `--remove` 只承认调用方显式回传的 listing 值，`AC-004` 的大小与身份两条校验才真正生效。

### t022_code_f003 - 参数循环末尾无条件 `shift` 在 `set -e` 下失败退出；未知分支残留失效变量 `arg`

- 严重度：minor
- 锚点：行为缺陷 —— 带值选项作为末参且缺值时，未按语义走到校验/交互默认，而是在解析循环内以 errexit 退出。
- 位置：`src/zmole/Resources/mole/bin/installer.sh:981`（循环尾 `shift`）、`:973`（`[[ -n "${arg:-}" ]]`）。
- 问题：
    - `--remove` / `--size` / `--identity` 分支内部已 `shift` 吃掉取值；若该选项是最后一个参数（例如单独 `--remove`），内层 `shift` 后 `$#=0`，循环尾 `:981` 的裸 `shift` 返回 1，`set -e` 直接终止脚本。实测 `... --remove` → `RC=1`，未经 `installer_remove_path` 的「非绝对路径」校验；`--size`/`--identity` 单独则应为交互默认，却同样 rc=1 退出。
    - 正常 GUI 调用（每选项都带值）不受影响，故非阻塞，但语义路径与注释「Non-interactive modes never enter the alt screen」之外的边界未被正确处理。
    - `:973` 的 `${arg:-}` 引用的是改写前 `for arg in "$@"` 遗留变量，在 `while` 循环内从未赋值，恒走 else 分支，属死分支/误导。
- 建议：把尾部 `shift` 改为条件 `[[ $# -gt 0 ]] && shift`，或在分支内显式处理缺值；删除 `:973` 的 `arg` 死分支，仅保留 `echo "Unknown option: $1"`。

### t022_code_f004 - 本地补丁使 `INSTALLER_SCAN_PATHS` 丢失 `readonly`，且 `MOLE_INSTALLER_SCAN_ROOT` 是生产可达的扫描覆盖

- 严重度：minor
- 锚点：行为缺陷（健壮性回归）—— 上游 `readonly INSTALLER_SCAN_PATHS=(...)` 变为普通赋值。
- 位置：`src/zmole/Resources/mole/bin/installer.sh:41-65`。
- 问题：为支持条件赋值，`INSTALLER_SCAN_PATHS` 由 `readonly` 改为可写全局；脚本内未见重赋值，功能无即时影响，但丢失了「扫描目录集合不可变」的守护（回归）。另外 `MOLE_INSTALLER_SCAN_ROOT` 注释自称「test-only」，实际未加 `MOLE_TEST_MODE` 门禁，任何环境均可收窄生产扫描根；虽同用户无提权，仍属注释与实现不一致的小隐患。
- 建议：在 if/else 之后补 `readonly INSTALLER_SCAN_PATHS`；若要保留 test-only 语义，把覆盖放进 `MOLE_TEST_MODE=1` 条件下，或更新注释说明其为受控的环境覆盖点。

## 结论

- 前轮 finding 复核：Round 1，无。
- 本轮新发现：4 条（important 2：f001、f002；minor 2：f003、f004）。
- 未进表的提示：
    - 文件过大：`src/zmole/Resources/mole/bin/installer.sh` 物理 1029 行（本 task 净增约 168 行），超「手写脚本 ≥800 → important」阈值；按规则不入 finding 表。该文件为上游捆绑脚本，本 task 增量限于 t022 补丁块，未引发可观测缺陷。
    - 复杂度：`main` 参数解析与 `installer_remove_path` 分支数偏高但未达需处理阈值，且未见分支漏处理。
    - `MOLE_DELETE_MODE=trash` 覆盖（`:927`）正确：无永久删除回退，符合 AC-005 与不变量；交互路径 diff 未触及，未发现 TUI 回归。
- 总体判断：交互路径未改、删除进废纸篓且无永久回退、JSON 逃逸与字段正确性均通过；但非交互接口在「空候选」（f001）与「调用方省略 size/identity」（f002）两条路径上分别产生非法输出/假成功与校验失效，均为 important 且未解决。仅 f003/f004 为 minor 时可 PASS，现不满足。
- 系统性 follow-up：无（f002 与 `t022_test_f001` 已分别从实现侧与测试侧覆盖，建议同一轮修复实现并补空夹具用例即可）。

verdict: FAIL

______________________________________________________________________

### Round 2 (2026-10-16T20:09:33+08:00)

- 复核对象：`git -C '/Users/karson/kar/code/zmole_t022' diff 770ea9aa58d07d4dbc1930669bdf7cdf520c0544`（相对 Round 1 增量集中在 `installer.sh`：空数组守卫、`--remove` 前置校验、`shift || true`、`arg` 死分支删除）。
- 门禁实跑：`bash tests/integration/installer_interface_test.sh` → **13 pass / 0**（脚本内 13 处 `pass`，与输出一致）；`bash tests/integration/clean_trash_test.sh` → pass；`pytest .repo_template/tests -q -m contract` → 147 passed。
- 独立复现（bash 3.2，非测试内），用于判定真修而非自述：
    - 空扫描 `--list-json` → stdout=`[]`、stderr 空、RC=0。
    - 空扫描 `--remove /tmp/r2file.txt --size 0 --identity x` → stderr=`No installer candidates in the current scan`、RC=1、原文件仍在（fail-closed）。
    - `--remove` 单独 → stderr=`Refusing to remove a non-absolute path`、RC=1（不再因循环尾 `shift` 触发 errexit）。
    - 列后改写大小 0→1234 后：`--remove <path> --size 0 --identity <listed>` → stderr=`Changed since scan (size)`、RC=1、原文件仍在；省 `--size` → stderr=`Removal requires the listed size and identity`、RC=1。size+identity 均正确时 RC=0 且移入测试废纸篓。

#### 前轮 finding 处置

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t022_code_f001|important|已修|`"${all_files[@]:-}"` 守卫 + `installer_list_json` 显式 `if ! collect…; then printf '[]'; fi` + `installer_remove_path` 空候选 fail-closed；bash 3.2 实测空扫描输出 `[]`、空 remove RC=1|`installer.sh:848/862/891-899`|
|t022_code_f002|important|已修|`--remove` 前置要求数字 size 且非空 identity，否则拒绝；`planned_size/identity` 直接取传入值，不再回退到重扫/当前值；实测改大小、省参数两条路径均被拒|`installer.sh:906-916`|
|t022_code_f003|minor|已修|带值选项与循环尾统一 \`shift||
|t022_code_f004|minor|已修（有意方案）|`readonly` 有意移除以允许测试环境收窄扫描根，属设计取舍；生产默认目录不变。附注：自述称改 `declare -a`，代码实为普通数组赋值（无 `declare -a`），二者无行为差异；`MOLE_INSTALLER_SCAN_ROOT` 的「test-only」注释与生产可达覆盖仍略有出入，属 minor 提示，不入表|`installer.sh:41-63`|

#### 回归扫描

- 交互路径未变：diff 仅触及扫描配置块、t022 新函数与 `main` 解析；`perform_installers`/`execute_installer_delete_plan` 等原样。
- 无永久删除回退：新路径唯一删除为 `MOLE_DELETE_MODE=trash mole_delete "$target" false`（`:937`）；全脚本无 `rm -rf`/`rm` 直删。
- 无 TUI 泄漏：`--list-json`/`--remove` 在 `hide_cursor`/alt-screen 之前 return（`:991-998`）；门禁新增 “no alt-screen/escape output” 用例覆盖。
- 新引入量未触及整数/路径边界问题；未发现新 finding。

#### 结论（Round 2）

- 前轮 finding 复核：f001/f002/f003 真修并经 bash 3.2 独立复现；f004 按有意的可写数组方案接受，残留仅为表述/注释层面的 minor 提示。
- 本轮新发现：0 条。
- 未进表的提示：`installer.sh` 仍 1035 行（超手写脚本 800 行阈值，规则同 Round 1，不入表）；`installer_remove_path` 的空候选守卫存在 `if ! collect…` 与紧随的 `[[ ${#INSTALLER_PATHS[@]} -gt 0 ]]` 双重判断（冗余但无害）。
- 总体判断：Round 1 的两条 important 均已消除，交互路径与「删除只进废纸篓、无永久回退、非交互不读键」不变量保持；无未解决 critical/important。

reviewed_scope: 9ea11152a01334fb

verdict: PASS
