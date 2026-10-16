---
tid: "t022"
slug: "installer_interface"
title: "安装包非交互接口"
status: "done"
branch: "t022_installer_interface"
worktree: ""
review_level: "full"
review_limit: "5"
verify_limit: "5"
diff_anchor: "770ea9aa58d07d4dbc1930669bdf7cdf520c0544"
depends_on: ""
conflicts_with: ""
note: "捆绑 installer 列出 JSON 并按预览路径移入废纸篓。"
---

# Task 过程总账

front matter 只经 `task.py` 修改；reviewer 只写对应 `review_*.md`。

## 实施笔记

执行期记录关键步骤、决策、验证、阻塞和用户批准的新轮次上限。

创建期不预测实施步骤。只记有追溯价值的内容；无事项时写“无”。

来源：docs/design/refactor_grilling.md。用户于 2026-10-16 批准后创建。

- 在 `bin/installer.sh` 增加本地补丁（标注 `zmole local patch (t022)`）：`--list-json` 输出候选 `{path,size_bytes,source,identity}`；`--remove <path> --size <n> --identity <id>` 只接受本次扫描中的绝对路径并强制核对大小与身份，删除显式 `MOLE_DELETE_MODE=trash`，失败保留原文件、无永久回退；非交互模式在进入 alt screen/读键前返回。
- 增加 `MOLE_INSTALLER_SCAN_ROOT` 测试钩子（仅收窄扫描根）；空数组按 bash 3.2 安全处理。
- 新增 `tests/integration/installer_interface_test.sh`（真实脚本子进程 + 临时扫描根/废纸篓），覆盖 dmg/普通 zip/payload zip、JSON 字段与无 TUI、按路径入篓、未列出/缺 size/改大小/身份不符四种拒绝、入篓失败保留、空扫描 `[]`。
- `docs/blueprint/testing.md` 加入该测试；`decisions.md` 追加 008；`architecture.md`/`domain.md` 更新安装包范围。
- 黑盒：该集成测试即可执行黑盒；未接 GUI（t023）。

## Review 处置

review_level=full：`review_code.md` / `review_test.md`。

|finding_id|severity|status|rationale|fix_ref|
|---|---|---|---|---|
|t022_code_f001|important|已修|空扫描在 bash 3.2 下崩溃/假成功，加空数组保护并 `[]`|installer.sh|
|t022_code_f002|important|已修|省略 size/identity 退化为空校验，改为强制要求|installer.sh|
|t022_code_f003|minor|已修|尾 `shift` 在 set -e 下退出 + 死变量，改 \`shift||
|t022_code_f004|minor|撤回|扫描路径改可变以支持测试收窄，生产默认不变|installer.sh|
|t022_test_f001|important|已修|补真实“列出后改大小”拒绝用例|installer_interface_test.sh|
|t022_test_f002|minor|已修|plain zip 改非空内容触达内容过滤|installer_interface_test.sh|
|t022_test_f003|minor|已修|no-TUI 断言加 ESC 序列检查|installer_interface_test.sh|
|t022_test_f004|minor|已修|未列出改用扫描根内真实非候选文件|installer_interface_test.sh|

## 收尾报告

### 验收与验证

- spec：[`spec.md`](spec.md)
- 结果：全部满足
- 测试：`bash tests/integration/installer_interface_test.sh`：13 cases 全过；`bash tests/integration/clean_trash_test.sh`：通过；`pytest .repo_template/tests -q -m contract`：147 passed
- 黑盒：集成测试即黑盒（真实 installer 子进程 + 临时扫描根/废纸篓）
- review：`review_code.md`（rounds 1-2）、`review_test.md`（rounds 1-2）最终均 PASS
- AC 证据：见 `handoff.json`

### 结果摘要

- 捆绑 installer 增加非交互列出与按路径删除：列出含 path/size/source/identity；删除只接受本次列出路径并核对大小与身份，移入废纸篓，失败保留原文件，不入 TUI。界面在 t023 消费该接口。遗留：无。
