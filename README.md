# Blue Hour｜蓝时归航

Godot 4.7（GDScript）2D 斜俯视小队生存原型：营地整备 → 选择任务 → 进入随机生成街区派工搜刮、战斗、救援 → 发动巴士集合撤离 → 回营结算（食物、成长、经济/建造）→ 再出击。机制参考 Deadly Days 一类游戏，但不包含其任何素材。

> 状态：未发布原型。数值均为临时值（PROJECT_TEMP）。存档格式随时可能变化，**不保证旧存档可读**。

## 运行

引擎版本固定为 `.godot-version`（4.7.2）。

```bash
# 直接用编辑器打开 project.godot，或：
python tools/godot.py run --godot <Godot 可执行文件>
```

只有一个入口，无需任何玩法参数。存档位于 `user://playable-v1/run.enemy-v1.json`。

操作：左键地面移动、点建筑派工/再点取消；WASD 移动镜头，滚轮缩放，空格暂停，Esc 暂停菜单。发动巴士后需全员到达才能归航。

## 测试

```bash
python tools/godot.py check --godot <Godot 可执行文件>   # 导入 + 启动 + 单元/契约测试 + 完整一局冒烟（tests/smoke_loop.gd）
```

所有输出写在被忽略的 `.local/` 下，不会碰真实玩家存档。

## 文档

- [AGENTS.md](AGENTS.md)：协作与代码约定
- [docs/architecture.md](docs/architecture.md)：当前架构与模块

历史里程碑文档、验收记录和截图已从仓库移除，需要时查看 git 历史。

美术为项目原创（含 AI 辅助生成、SVG 与代码绘制），音效为数学合成；逐文件来源与 SHA 见 `assets/PROVENANCE.json`。本仓库暂无 LICENSE，公开可见不代表授予复制、分发或商用许可。
