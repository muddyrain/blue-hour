# Blue Hour 协作约定

Godot 4.7.2（版本锁在 `.godot-version`）+ 类型化 GDScript 的原型项目。先读 `README.md` 和 `docs/architecture.md`。

## 命令

```bash
python tools/godot.py run   --godot <engine>                 # 启动游戏（唯一入口）
python tools/godot.py check --godot <engine>                 # 导入 + 启动 + 测试，提交前必跑
python tools/playable_flow.py --godot <engine> --output .local/pf   # 完整一局冒烟（改动玩法/存档/流程时跑）
<engine> --headless --path . --editor --import --quit        # 只做解析检查（最快）
```

所有测试产物放 `.local/`（已忽略），不要用真实玩家存档测试。

## 代码约定

- 类型化 GDScript，显式依赖；不加 Autoload。
- 新代码放进 `src/features/<feature>/`，不要继续往 `src/app/main.gd` 和 `src/features/expedition/expedition.gd` 里堆逻辑。
- 只有一个入口和一种存档格式。不要再加 `--bh-*` 试验开关、平行的“旧版/新版”分支或版本分叉。
- 原型阶段允许存档断档：改格式时直接改，不写迁移代码，不为旧档保留兼容分支。
- 数值都是临时值，改数值要在 PR 里说明。
- 不提交调试打印；需要给测试读取的机器标记用 `BH_` 前缀并在测试里引用。
- 新增美术/音频登记到 `assets/PROVENANCE.json`。

## 工作方式

- 任务保持小而聚焦：一个 PR 一件事，先做最小可验证改动。
- 验证按影响范围：先解析检查和相关单测，最后跑一次 `check`；涉及流程/存档时再跑 `playable_flow`。不要为普通改动跑大规模矩阵或反复重跑。
- 不要新增里程碑合同文档、验收报告或截图归档；需要说明的写在 PR 描述里，长期有效的结构信息更新到 `docs/architecture.md`。
- Git：从 `main` 拉分支，不重写已推送历史，不强推；推送、开 PR、合并分别需要明确授权。
