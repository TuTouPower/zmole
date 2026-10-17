# d001 mole 无 TTY 机器接口（V1.55.0）

- 来源：s001 spike + 源码复核 + 命名 uninstall dry-run
- 结论：
    - status/analyze/uninstall --list 为 JSON（list 的 `size` 是人类可读字符串）。
    - history 顶层 `{logs,limit,sessions,deletions}` 已见；元素字段以 `history.sh` 为准，运行样例曾为空。
    - clean dry-run 写 `$HOME/.config/mole/clean-list.txt`。
    - optimize dry-run 为文本。
    - purge：非 TTY 自动选非近期，不读 stdin；`--yes` 只放行真实执行。预览用 `--dry-run`，执行用 `--yes`。
    - 命名 uninstall：空 stdin 在 `[y/N]` 失败；stdin `y\n` 可完成 dry-run。匹配按名称取首个精确/子串命中，path 才是身份。
    - 捆绑钉 tag `V1.55.0`（`69ab325d`），勿把研究仓 `0659e906` 当成同一快照。
- 证据：`docs/archive/spikes/s001_mole_cli_fixtures/report.md`（原 `docs/spikes/…`，已随 spike 迁档）、`samples/`、`lib/clean/project.sh` 1682/2518、`bin/uninstall.sh` `match_apps_by_name` 与确认提示（原 1767 行；t029 补丁后约 1887 行——行号随捆绑补丁漂移，请按符号 `match_apps_by_name` / `Proceed with uninstallation?` 定位）。
- 影响：t002/t005/t009/t011 argv 与身份规则；t013 验双架构。
- 现状：有效
