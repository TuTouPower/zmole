# Spike report

## 问题

无 TTY、无 sudo 时，mole 1.55.x 只读/预览命令的真实输出是什么，GUI 能否当数据用。

## 成功判据

- 每条命令有退出码与样例
- JSON 关键字段已记录，或标明「仅空态 / 改以源码为准」
- purge dry-run 是否可预览有**与源码一致**的结论

## 尝试

- 本机无 `mo`、无 `go`。Bash 入口用 `~/kar/github_repo/mole/mole`，当时 HEAD **`0659e906`（main，不是 tag）**，`VERSION` 字符串仍为 1.55.0。
- `status`/`analyze` 用 GitHub Release **tag `V1.55.0` / `69ab325d`** 的 `binaries-darwin-arm64.tar.gz`。
- **产品捆绑不得混用这两份**：t002 钉死 tag `V1.55.0`（`69ab325d`）的 Bash 树 + 同 tag Go 二进制。本 spike 的 Bash 行为以源码+实测为准，若与 tag 有 diff 以 tag 为准并在 t002 核对。
- 全部 `stdin` 为空（非 TTY），另对命名 uninstall dry-run 补测了 `y\n`。`HOME` 指到 `.scratch/s001/home`（uninstall 列表/dry-run 扫的是真实 `/Applications`）。`MOLE_TEST_NO_AUTH=1`。

## 证据

|命令|exit|耗时|结构化？|备注|
|---|---|---|---|---|
|`mole --version`|0|1.1s|文本|`Mole version 1.55.0`|
|`status --json`|0|5.7s|JSON 对象|含 `health_score`/`cpu`/`memory`/`disks`；Go 二进制来自 tag|
|`analyze --json <path>`|0|0.6s|JSON|`overview: false`|
|`analyze --json` overview|0|5.6s|JSON|`overview: true`|
|`history --json --limit 5`|0|0.4s|JSON 顶层|**sessions/deletions 皆空**；元素字段见源码 `history_render_json_*` 与 `samples/history_json.schema_from_source.json`|
|`uninstall --list`|0|36s|JSON 数组|`name`/`bundle_id`/`source`/`uninstall_name`/`path`/`size`（人类可读）|
|`uninstall --dry-run <name>` 空 stdin|1|~33s|中止|停在 `Proceed with uninstallation? [y/N]`|
|`uninstall --dry-run <name>` stdin=`y\n`|0|~33s|文本预览|列出将删路径；随后 n1 遇 EOF 当 Enter，dry-run 收尾|
|`clean --dry-run`|0|12s|摘要 + 文件|`$HOME/.config/mole/clean-list.txt`|
|`optimize --dry-run`|0|4.8s|文本|exit 0|
|`purge --dry-run`|0|0.9–2.2s|视候选而定|不卡。空名单是因为 **没有合格非近期候选**，不是 EOF。非 TTY 自动勾选非近期，不读 stdin。`--yes` 只放行**非 dry-run** 执行|

`clean-list.txt` 含分段标题与 `path  # size` 行。

## 结论

1. status / analyze / uninstall --list 可直接解码。analyze 的 `--json` 必须在路径前。
2. history **顶层形状**已核实；**单条 session/deletion 未从运行抓到**，以实现/测试用源码字段表。
3. clean 预览读本次 `clean-list.txt` 可行。
4. optimize 预览用 stdout 文本。
5. **purge：`--yes` 不是预览条件。** 预览 `purge --dry-run`；执行 `purge --yes`。
6. **uninstall 命名路径必须 stdin=`y\n`**，否则预览/执行都完不成。禁止因此改用 PTY。
7. 捆绑钉 **`V1.55.0` / `69ab325d`**，不要用研究仓 `0659e906`。

可信度：JSON/list/clean/optimize 高；history 元素字段为源码推导；purge 空名单因果以源码为准（未在相同候选上做 `--yes` 对照重跑）。

## 是否采纳

- 决定：是（按上文修正后的结论）
- 理由：可脚本化表面足够做第一版；卸载要 stdin 协议与身份校验
- 后续 task：t002 钉 tag；t009 用 `y\n` + path 身份；t011 预览不加 `--yes`；t005 用源码字段夹具
