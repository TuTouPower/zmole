# Spike report

## 问题

无 TTY、无 sudo 时，mole 1.55.x 只读/预览命令的真实输出是什么，GUI 能否当数据用。

## 成功判据

- 每条命令有退出码与样例
- JSON 关键字段已记录
- `purge --dry-run` 是否可预览有明确结论

## 尝试

- 本机无 `mo`、无 `go`。Bash 入口用 `~/kar/github_repo/mole/mole`（当时 `main` @ `0659e906`，`VERSION=1.55.0`）。
- `status`/`analyze` 用 GitHub Release `V1.55.0` 的 `binaries-darwin-arm64.tar.gz`（`.scratch/s001/bin/`，不入库）。
- 全部 `stdin` 为空（非 TTY）。`HOME` 指到 `.scratch/s001/home`，`MOLE_TEST_NO_AUTH=1`，避免写用户主目录、避免 sudo 对话框。
- 原始输出在 `.scratch/s001/raw/`（gitignore）。脱敏/截断样例在 `samples/`。

## 证据

|命令|exit|耗时|结构化？|备注|
|---|---|---|---|---|
|`mole --version`|0|1.1s|文本|`Mole version 1.55.0`|
|`status --json`|0|5.7s|JSON 对象|含 `health_score`；直接跑 Go 二进制|
|`analyze --json <path>`|0|0.6s|JSON|`overview: false`，有 `entries`/`large_files`/`total_files`|
|`analyze --json` overview|0|5.6s|JSON|`overview: true`，有 `entries`/`total_size`，无 `total_files`|
|`history --json --limit 5`|0|0.4s|JSON|`logs`/`sessions`/`deletions`；空仓 sessions=[]|
|`uninstall --list`|0|36s|JSON **数组**|字段 `name`/`bundle_id`/`source`/`uninstall_name`/`path`/`size`（size 是人类可读字符串）|
|`clean --dry-run`|0|12s|终端摘要 + 文件|写出 `$HOME/.config/mole/clean-list.txt`；无 sudo 则跳过系统缓存|
|`optimize --dry-run`|0|4.8s|终端文本|无 JSON；可滚动展示；exit 0|
|`purge --dry-run`|0|0.9–2.2s|几乎无名单|**不卡住**；EOF 视为未勾选 → `No items selected`|
|`purge --dry-run --yes`|0|1.9s|文本名单|有候选时打印 `✓ [DRY RUN] path, size` 与汇总；**不删除**|

`clean-list.txt` 含分段标题与 `path  # size` 行，末尾 Summary。

## 结论

1. status / analyze / history / uninstall --list 可直接 `Codable`。`--json` 必须在 analyze 的路径参数前（本 spike 如此调用成功）。
2. clean 预览读 `clean-list.txt` 可行（相对 `$HOME`）。
3. optimize 预览只能展示 stdout 文本。
4. **purge：无 TTY 不卡死。** 仅 `--dry-run` 没有名单。预览必须 `purge --dry-run --yes`；执行 `purge --yes`。t011 按此改 argv，不必 park。
5. 捆绑 mole 时 Go 辅助程序用 Release 的 `analyze-darwin-{arm64,amd64}` 与 `status-darwin-*`，放入 `bin/analyze-go` / `bin/status-go`（或 mole 安装布局要求的名字）。

可信度：高（本机实测）。限制：HOME 隔离，clean/purge 扫描到的路径不是用户真盘全量；uninstall 名单来自真实 `/Applications`（样例已脱敏）。

## 是否采纳

- 决定：是
- 理由：第一版所列命令都有可用输出；purge 预览要带 `--yes`
- 后续 task：t004–t011 按 `samples/` 解码；t011 预览 argv 改为 `--dry-run --yes`；t002 用 Release 双 arch Go 二进制
