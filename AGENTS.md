# Blue Hour 协作约定

Godot 4.7.2（版本锁在 `.godot-version`）+ 类型化 GDScript 的原型项目。先读 `README.md` 和 `docs/architecture.md`。

## 命令

```bash
python tools/godot.py run   --godot <engine>                 # 启动游戏（唯一入口）
python tools/godot.py check --godot <engine>                 # 导入 + 启动 + 测试 + 完整一局冒烟，提交前必跑
<engine> --headless --path . --editor --import --quit        # 只做解析检查（最快）
```

所有测试产物放 `.local/`（已忽略），不要用真实玩家存档测试。

## 代码约定

- 类型化 GDScript，显式依赖；不加 Autoload。
- 新代码放进 `src/features/<feature>/`。`main.gd` / `expedition.gd` 只是协调层：逻辑放进对应的 `app_*.gd` / `expedition_*.gd` helper（单文件尽量 < 600 行），根上只留状态、信号和一行转发；约定见 `docs/architecture.md`。
- 手感与美术改动只改表现模块（`expedition_feedback.gd`、`expedition_ui.gd`、`app_presentation.gd`、`app_results.gd`），不要混进规则代码。
- 只有一个入口和一种存档格式。不要再加 `--bh-*` 试验开关、平行的“旧版/新版”分支或版本分叉。
- 原型阶段允许存档断档：改格式时直接改，不写迁移代码，不为旧档保留兼容分支。
- 数值都是临时值，改数值要在 PR 里说明。
- 不提交调试打印；需要给测试读取的机器标记用 `BH_` 前缀并在测试里引用。
- 新增美术/音频登记到 `assets/PROVENANCE.json`。

## 工作方式

- 任务保持小而聚焦：一个 PR 一件事，先做最小可验证改动。
- 验证按影响范围：先解析检查和相关单测，最后跑一次 `check`；`check` 已包含完整一局冒烟 `tests/smoke_loop.gd`，改动流程/存档时务必让它通过。不要为普通改动跑大规模矩阵或反复重跑。
- 不要新增里程碑合同文档、验收报告或截图归档；需要说明的写在 PR 描述里，长期有效的结构信息更新到 `docs/architecture.md`。
- Git：从 `main` 拉分支，不重写已推送历史，不强推；推送、开 PR、合并分别需要明确授权。
