# 当前生效 spec 清单

在表即生效。每个 task 收尾时写入或更新对应行（须已过黑盒）；废弃时整行删除，spec 移入 `docs/archive/specs/`。历史清单由 `docs/archive/specs/` 目录承载。替代旧需求时在 `supersedes` 列填旧 slug；无则填 `-`。

|slug|task 清单|最后更新时间|supersedes|
|---|---|---|---|
|app_shell|t001, t003, t014→t015, t035, t044|2026-10-17|-|
|mole_bridge|t002, t025, t027, adoption-review|2026-10-17|-|
|status|t004, t016, t037|2026-10-17|-|
|history|t005, t024, t038|2026-10-17|-|
|disk_analyze|t006, t020, t028, t032|2026-10-17|-|
|clean|t008, t017, t018, t044|2026-10-17|-|
|uninstall|t009, t019, t029, t044|2026-10-17|-|
|optimize_purge|t010, t011, t021, t044|2026-10-17|-|
|installers|t022, t023, t030|2026-10-17|-|
|whitelist|t007, t024, t044|2026-10-17|-|
|overview|t016, t026, t034, t036, t044|2026-10-17|-|
|prewarm|t031, t043|2026-10-17|-|
|release_icon|t012, t013, t033|2026-10-17|-|
|settings|t003, t024|2026-10-17|-|

说明：t014 的视觉改版被 t015 的侧边栏基线整合取代；t037–t039 并入 t035 的 UI 对齐工作，行为契约已合入对应域 spec。
