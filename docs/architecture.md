# 架构（当前状态）

本文只描述仓库现状；历史里程碑合同、验收记录已移除（见 git 历史）。

## 入口与流程

- `project.godot` → `src/app/main.tscn` / `src/app/main.gd`：唯一入口。负责标题、营地、任务选择、出击生命周期与回营结算的编排。
- `src/app/playable_entry.gd`：固定存档目录 `user://playable-v1/`（`run.enemy-v1.json` 与 `audio.json`）。命令行只接受 `--bh-progress=` / `--bh-audio-settings=` 覆盖路径（测试用）。
- 一局循环：营地（`camp`/`camp_scene`/`loadout`/`survivors`）→ `MissionSelect` 选当日行动 → `Expedition`（`src/features/expedition/expedition.gd`）运行街区：派工搜刮、战斗、救援、夜间压力 → 巴士集合撤离 → `FrozenSettlement` 计算结算 → `RunTransaction` 写入存档 → 回营。

`main.gd`（约 2.5k 行）和 `expedition.gd`（约 2.8k 行）仍然过大，计划在下一轮按职责拆分。

## 模块（`src/features/`）

| 目录 | 职责 |
| --- | --- |
| `worldgen/` | 当前地图生成：`WorldgenLayout`（布局 v5）→ `WorldgenGeometry` 道路/地块切分 → `ThemedDistrict` / `WarehouseDistrict` / `SeededWarehouseDistrict` / `IndustrialYard` / `RescueCourt` 等街区类型，`Worldgen*` 地面/摆设/美术。新旅程固定使用 `WorldgenState.initial_build(seed, true, true)`（BH_LEVEL_V1 + 工业场）。 |
| `exploration/` | 探索行动（daily action v9）、站点/道具/目标、`ExplorationLayout` 导航与校验、`LevelSummary`。 |
| `rogue/` | `DailyActions` 行动派发（只剩 Exploration / Investigation 两条），以及仍被当前数据结构复用的旧行动/布局工具类（`TaskActions`、`WeaponActions`、`NeighborhoodLayout`、`WorldLayout` 等）。 |
| `campaign/` | 短流程战役规则 `CampaignRules/CampaignState`、调查日、事件出击、侦察、路障、广告牌、跨日压力。 |
| `expedition/` | 场内运行时：角色/敌人、导航、巴士撤离 `BusJourney`、镜头、出击快照 `SortieSnapshot`（暂存/恢复）。 |
| `expedition_hud/` | 场内 HUD。 |
| `combat_v1/`, `encounter/` | 战斗规则与运行时（武器、毒气、爆发、尖叫者、遭遇终止）。 |
| `search/` | 多人派工搜刮。 |
| `basic_support/`, `powers/`, `persona/` | 支援技能、特殊能力、人物特质/角色。 |
| `build/`, `items/`, `economy/` | 出发构筑、物品定义、经营/建造（M48 经济：回收、出售、设施、自制枪）。 |
| `camp/`, `camp_scene/`, `loadout/`, `survivors/` | 营地规则与面板、营地场景、武器仓/配装、幸存者名册/成长/训练。 |
| `finale/` | 终局抽水站。 |
| `survival/` | 生存合同/数值辅助。 |
| `presentation/` | 通用表现与样式。 |
| `audio_settings/` | 音量设置与合成音效服务。 |
| `run_save/` | 存档：`ProductionProgress`（会话）+ `RunTransaction` + `ReceiptJournal`（带哈希的收据日志）+ `*State` 校验链。 |

### 存档说明

- 不再兼容旧存档：v1–v5 `RunSave` 升级、v5 迁移导入、旧位置 `user://saves/run.json` 保护都已删除。读到不认识的存档会被拒绝，需要开新旅程。
- 当前存档的校验仍是“新状态投影到旧校验器”的链式结构（`EnemyState → WeaponState → …`），收据日志仍做哈希校验。这一部分与当前存档格式耦合，未在本轮删除；后续可整体替换为简单的单文件 JSON 存档。

## 资源

- `assets/`：运行时美术/音频。逐文件来源与 SHA 登记在 `assets/PROVENANCE.json`，`tools/validate_assets.py` 校验（`check` 会运行）。
- 美术为项目原创：AI 辅助生成的 PNG（统一透明裁切、等比缩放、登记脚点后入图集，见各目录 `atlas.json`/`manifest.json`）、手绘 SVG、代码绘制；音效由 `src/features/audio_settings/generate_cues.py` 数学合成。生图提示要点在 `assets/world_v1/source/PROMPTS.md`、`assets/world_v2/source/prompts.md`。
- 不使用 Deadly Days 的任何图像、声音或录屏。

## 测试与工具

- `tools/godot.py check`：导入、启动（`BH_READY`）与 `tests/` 下的单元/契约测试，任何 `SCRIPT ERROR`/`ERROR` 或 `"failures": N>0` 都判失败。
- `tests/smoke_loop.gd`（在 `check` 中）：无头跑完整一局：新档 → 出击 → 搜刮 → 战斗 → 巴士撤离 → 结算 → 重启读档 → 第二次出击；任何 SCRIPT ERROR 都会判失败。
- `persona_ui` 在 main 上就已失败（1024×640 营地详情滚动高度 <140px），属已知问题。
- 其他 `tools/*_flow.py` 是历史上针对单个系统的流程脚本，未纳入 `check`，部分在 main 上已经失效，后续可继续清理。
