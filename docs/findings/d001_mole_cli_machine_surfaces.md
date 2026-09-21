# d001 mole 无 TTY 机器接口（V1.55.0）

- 来源：s001 spike
- 结论：status/analyze/history/uninstall --list 为 JSON；clean dry-run 写 `~/.config/mole/clean-list.txt`；optimize dry-run 为文本；purge 预览必须 `purge --dry-run --yes`，执行 `purge --yes`。仅 `purge --dry-run` 会得到空选。
- 证据：`docs/spikes/s001_mole_cli_fixtures/report.md` 与 `samples/`。实测 stdin 非 TTY、`MOLE_TEST_NO_AUTH=1`。Go 辅助程序来自 Release `V1.55.0` darwin-arm64。
- 影响：t002 捆绑 `analyze-go`/`status-go`；t004–t010 按 samples 解码；t011 预览 argv 含 `--yes`。uninstall 的 `size` 是人类可读字符串。
- 现状：有效
