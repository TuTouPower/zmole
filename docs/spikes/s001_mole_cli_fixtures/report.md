# Spike report

## 问题

无 TTY、无 sudo 时，钉死版本 mole（目标 `V1.55.0`）只读/预览命令的真实输出是什么，GUI 能否当数据用。

必须实测：

- `mole --version`
- `mole status --json`
- `mole analyze --json`（overview 与一路径；`--json` 在 PATH 前）
- `mole history --json --limit 5`
- `mole uninstall --list`（stdout 非 TTY）
- `mole clean --dry-run` 是否写出 `~/.config/mole/clean-list.txt`
- `mole optimize --dry-run` 退出码与摘要是否可展示
- `mole purge --dry-run` 在 stdin 非 TTY 时是否返回、是否卡在选择器

禁止真实删除。禁止解析 TUI 帧。

## 成功判据

- 每条命令有退出码、stdout/stderr 样例（可脱敏）落在本 spike 目录
- 写明 JSON 关键字段或「无结构化输出」
- 对 `purge --dry-run` 给出明确结论：GUI 可预览 / 不可预览须 park `purge_run`

## 尝试

- 未跑。优先用本机已装 `mo` 若版本匹配；否则用 `~/kar/github_repo/mole` 源树 `./mole`。

## 证据

- 未采集。

## 结论

- 未完成。

## 是否采纳

- 决定：未定
- 理由：尚未跑命令
- 后续 task：t004–t011 的 JSON/文本解码以本 spike 的 findings 为准
