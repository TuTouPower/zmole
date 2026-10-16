# Test Review — t022 installer_interface

- task: t022
- review_level: full
- diff_anchor: `770ea9aa58d07d4dbc1930669bdf7cdf520c0544`
- 被测：`tests/integration/installer_interface_test.sh`（intent-to-add），生产逻辑 `src/zmole/Resources/mole/bin/installer.sh`
- 审查角色：TEST reviewer（只读）
- 执行：`bash tests/integration/installer_interface_test.sh` → 10 pass / exit 0

## 方法与证据

- 实跑测试（10 pass）与 `tests/integration/clean_trash_test.sh`。
- 红灯光照：把 `770ea9a` 的 anchor `installer.sh`（含当前 `lib/`）抽出，`--list-json` / `--remove` 均 `Unknown option` rc=1；故 5 条 AC 的每个用例在 anchor 上均为红，patched 上转绿，属真实红→绿门禁。
- 危险模式扫描：测试无 `rm`、`dd`、`sudo`、无对 `$HOME`/`/etc` 等真实路径写入；`HOME`、`MOLE_TEST_TRASH_DIR` 全部指向 `mktemp -d` 临时树；`chmod 500` 后恢复 700。无越界破坏性操作。
- 独立复现（非测试内的对照实验），用于判定被测覆盖是否真实触达生产逻辑。

## Findings

### t022_test_f001 — important — spec 指定的「列出后被改写大小」场景未被执行，掩盖 AC-004 违规调用模式

- 症状 1：`spec.md` 测试策略要求夹具含「一个列出后被改写大小的文件」，但 `installer_interface_test.sh:88` 用硬编码 `--size 99999` 代替「改写文件大小」，夹具（`:23-28`）中不存在被改写的文件。
- 症状 2：`installer_interface_test.sh:85` 计算 `REAL_SIZE` 后从未使用；`:81` 的 `run_installer --list-json >/dev/null` 亦无作用（`--remove` 会重新扫描）。二者是「本应做改写对照」的残留痕迹。
- 后果（复现）：list 时 size=0，列出后把文件写成 1234 字节，再 `--remove <path> --identity <listed>`（不传 `--size`）→ rc=0，文件被移入废纸篓。因实现 `installer.sh:906` 在缺 `--size` 时回退到「本次重扫的大小」（`${INSTALLER_SIZES[$idx]}`），与 `:918` 的当前大小恒等，`AC-004` 的「大小与列出时不同则不删除」被绕过。
- 测试只覆盖了「调用方显式传错 size」这一分支，未覆盖 spec 指定的真实场景，因此该 AC 违规调用模式不会被门禁捕获。
- 建议：夹具新增一个列出后被改写的文件；分别用「传列出时的 size」与「只传 identity 不传 size」调用 `--remove` 并断言拒绝、原文件仍在。该用例应在当前实现上转红。

### t022_test_f002 — minor — AC-001「普通 zip」夹具是 0 字节空文件，未触达内容判定分支

- `installer_interface_test.sh:24` 用 `: > "$SCAN/plain.zip"` 生成空文件，非含非安装包内容的合法 zip。`is_installer_zip` 对空/非法 zip 在列目录阶段即失败返回 1，与「合法 zip 无安装包条目」走的是同一返回值但不同原因，故断言 `has_plain=False` 未真正验证内容过滤。
- 独立复现：合法 `ordinary.zip`（仅 `readme.txt`）正确被排除，说明实现无问题，属**测试保真度**缺口而非 impl bug。
- 建议：夹具改为 `zip` 打包一个非安装包文件（如 `readme.txt`），与 `payload.zip` 形成内容对照。

### t022_test_f003 — minor — AC-002「不进入全屏选择界面」证据间接且不能发现 stderr 侧回归

- `installer_interface_test.sh:44` 仅断言输出首字节为 `[`，且 `:42` 将 stderr 丢弃（`2>/dev/null`）。若回归在 JSON 之前向 stderr 打印菜单横幅/alt-screen 序列（`\033[?1049h`），该用例仍会通过。
- 因 stdout 非 tty，`[[ -t 1 ]]` 本就为假，alt screen 不会触发，此路径受环境限制；但可低成本加固。
- 建议：断言输出中不含 alt-screen/光标隐藏转义序列，并用 `timeout` + `< /dev/null` 运行，验证进程不阻塞读取按键。

### t022_test_f004 — minor — AC-004「不在本次列出结果中」用非安装包、且不落在扫描根的文件探测，分支判别偏弱

- `installer_interface_test.sh:82-83` 以 `$HOME/random.txt` 探测：既非安装包、又不在 `MOLE_INSTALLER_SCAN_ROOT`，其被拒更多来自「根本不在扫描结果」而非「不在本次 listing」。
- 且实现在 `--remove` 时重新扫描（`installer.sh:891`），并不存在固定「本次 listing」集合；测试无法区分「列出过的集合」与「实时扫描集合」。
- 建议：至少用落在扫描根内、但列出后被移出/未出现在该次 listing 的安装包路径探测，明确拒绝语义。

## 结论

### AC 覆盖

|AC|用例|判定|
|---|---|---|
|AC-001|dmg 出现、含 pkg 的 zip 出现、普通 zip 不出现（`:62-64`）|dmg / payload.zip 覆盖扎实；「普通 zip 不出现」夹具退化（见 f002），**部分覆盖**|
|AC-002|JSON 首字节、绝对路径 / size / source / identity 真值（`:44,:57`）|字段与绝对路径覆盖；「不进 TUI」证据间接（见 f003），**部分覆盖**|
|AC-003|移入测试废纸篓、原路径不存在（`:71-77`）|完整；且能区分「永久删除」回归|
|AC-004|未列出 / size 不符 / identity 不符 三分支拒绝且保留原文件（`:86-94`）|未列出与 identity 分支可；size 分支未覆盖 spec 指定场景，实测存在绕过（见 f001/f004），**不充分**|
|AC-005|不可写废纸篓导致移动失败，原文件保留（`:96-109`）|完整；`MOLE_TEST_TRASH_DIR` 覆盖生效，判别真实|

### 其他

- 红灯光照：5 条 AC 全部在 anchor（`770ea9a`）上红，patched 上绿。
- 测试可信度总体较高：真跑捆绑 `installer.sh` 子进程、隔离 HOME/废纸篓、无危险模式；主要缺口是 `AC-004` 未忠实复现 spec 测试策略，并因此放行一个会删除「列出后已改大小」文件的实际调用模式。
- 无 cleanup trap，`mktemp -d` 临时目录会残留，属卫生问题，非门禁项。

verdict: FAIL

______________________________________________________________________

## Round 2 (2026-10-16T20:08:28+08:00)

### 复核范围

- 重跑 `git -C zmole_t022 diff 770ea9aa58d07d4dbc1930669bdf7cdf520c0544`：测试扩到 164 行；impl `installer_remove_path` 已加「必须同时提供 listing 时的 size 与 identity」硬校验（`installer.sh`：`[[ "$expected_size" =~ ^[0-9]+$ && -n "$expected_identity" ]]`）。
- 门禁：`bash tests/integration/installer_interface_test.sh` → exit 0；`uv run --with pytest pytest .repo_template/tests -m contract -q` → 147 passed。
- 差异：任务描述称「14 pass」，实测 `pass()` 计数为 **13**（新增 no-escape / missing-pair / empty-scan 三项，`size mismatch` 用例被改写为 `size change after listing`，非新增）。功能门禁仍 exit 0，仅计数口述有偏差。

### 处置确认

|finding_id|severity|status|rationale|
|---|---|---|---|
|t022_test_f001|important|已修|测试 `:113-119` 先 list、`printf 'x' >> "$DMG"` 真实改大小，再以列出时的 size/identity 调 `--remove`，断言拒绝且文件仍在；另加 `:113-114` 缺 size/identity 被拒用例。impl 同步收紧为强制成对校验，round 1 实测的「缺 `--size` 即误删改大小文件」调用模式已封闭|
|t022_test_f002|minor|已修|`:26-34` plain.zip 现由 `zip -r` 打包 `readme.txt`（合法 zip 无安装包内容），payload.zip 打包 `Setup.pkg`，内容过滤分支被真实触达|
|t022_test_f003|minor|已修|`:60-71` 捕获 stderr 到 `list.err`，对 stdout+stderr 合并断言无 `\033`（ESC/alt-screen）序列，补上 stderr 侧回归探测|
|t022_test_f004|minor|已修|`:110` 改用扫描根内真实文件 `$SCAN/notes.txt`（非安装包候选）探测，配合 size/identity 参数，拒绝语义比 round 1 的扫描根外 `$HOME/random.txt` 更贴近|

### 新增 finding

无。

### 残余观察（不构成 finding）

- `notes.txt` 仍属「非安装包候选」而非「曾列出后被移出」的路径；因 `--remove` 采用实时重扫、无 listing 快照，此为当前设计下最贴近的探针，可接受。
- `:151` 新增 `rm -f "$SCAN"/*`，作用域限于 `mktemp -d` 的临时 `$HOME/Downloads`，无越界删除；no-escape 断言仅覆盖普通 list 调用，未覆盖 remove/空扫场景，均非门禁缺口。

### AC 覆盖（Round 2）

|AC|判定|
|---|---|
|AC-001|充分：dmg 出现、真·普通 zip（含 readme.txt）排除、含 pkg 的 zip 出现，内容过滤真实触达|
|AC-002|充分：JSON 首字节、绝对路径 / size / source / identity、无 ESC/alt-screen 输出、空扫 `[]`|
|AC-003|充分：移入测试废纸篓、原路径消失，可区分永久删除回归|
|AC-004|充分：未列出、缺 size/identity、列出后改大小、identity 不符 四分支均拒绝且保留原文件|
|AC-005|充分：不可写废纸篓致移动失败，原文件保留|

红灯光照：新增用例在 anchor（`770ea9a`）上同样为红（`--list-json`/`--remove` 均 `Unknown option` rc=1），patched 上绿。

reviewed_scope: 9ea11152a01334fb

verdict: PASS
