# 架构（当前状态）

本文只描述仓库现状；历史里程碑合同、验收记录已移除（见 git 历史）。

## 入口与流程

- `project.godot` → `src/app/main.tscn` / `src/app/main.gd`：唯一入口。负责标题、营地、任务选择、出击生命周期与回营结算的编排。
- `src/app/playable_entry.gd`：固定存档目录 `user://playable-v1/`（`run.enemy-v1.json` 与 `audio.json`）。命令行只接受 `--bh-progress=` / `--bh-audio-settings=` 覆盖路径（测试用）。
- 一局循环：营地（`camp`/`camp_scene`/`loadout`/`survivors`）→ `MissionSelect` 选当日行动 → `Expedition`（`src/features/expedition/expedition.gd`）运行街区：派工搜刮、战斗、救援、夜间压力 → 巴士集合撤离 → `FrozenSettlement` 计算结算 → `RunTransaction` 写入存档 → 回营。

## 组合方式：根节点 = 协调层 + 职责 helper

`main.gd` 与 `expedition.gd` 只保留共享状态变量、信号、`_ready`/`_process`/输入分发和一行转发方法；逻辑放在同目录的 `RefCounted` helper 里。约定：

- helper 在成员声明处构造（`var _camp: AppCamp = AppCamp.new(self)`），`_init` 只保存显式回指引用；测试可以不入树直接调用根方法。
- 公开方法、信号/按钮连接的方法、测试和其他模块用到的方法都留在根上做同签名转发；helper 之间互调也经根转发（保留测试子类的覆写）。
- 根上的协程转发要 `await` helper。
- 规则/模拟与表现分开：手感（顿帧、震屏、动画、音效）和 2.5D 换皮只应改表现模块（`ExpeditionFeedback`、`ExpeditionUi`、`AppPresentation`、`AppResults`），不碰规则模块。

### `src/app/`（`Main`）

| 文件 | 职责 |
| --- | --- |
| `main.gd` | 协调层：应用阶段状态、输入分发、转发 |
| `app_session.gd` | 启动/命令行参数、存档会话、新旅程、读档/备份、事务落盘 |
| `app_sortie.gd` | 任务选择 → 出击生命周期 → 出击事件接线 → 暂存/挂起 → 结算确认回营 |
| `app_results.gd` | 战斗结果、抽水站胜利与结算文本（表现） |
| `app_camp.gd` | 营地场景与设施、名册/成长/训练、配装/维修/改装、构筑与能力编辑 |
| `app_presentation.gd` | 标题画面与通用表现刷新（表现） |
| `app_menus.gd` | 暂停、退出确认、音量设置、返回标题 |

### `src/features/expedition/`（`Expedition`）

| 文件 | 职责 |
| --- | --- |
| `expedition.gd` | 协调层：场内共享状态、信号、`step()` 编排、转发 |
| `expedition_world.gd` | 场景/角色/建筑/抽水站构建（`_ready` 的世界搭建） |
| `expedition_orders.gd` | 玩家输入、选择、移动/搜刮指令、支援瞄准、队形目标 |
| `expedition_squad.gd` | 派工搜刮作业、站点查询、事件站点选择 |
| `expedition_combat.gd` | 战斗循环：目标选择、攻击判定、远程命中结算 |
| `expedition_threat.gd` | 刷怪、夜间压力、敌人寻路、空投/任务波次 |
| `expedition_extraction.gd` | 巴士集合/登车/撤离与出击结束 |
| `expedition_support.gd` | 支援、能力、构筑、急救、路障、侦察规则 |
| `expedition_feedback.gd` | 表现：射击/命中特效、飘字、通知、夜间光照、镜头、能力/侦察展示（未来顿帧/震屏/音效挂这里） |
| `expedition_ui.gd` | 表现：HUD 构建与刷新、文本格式化 |

## 模块（`src/features/`）

| 目录 | 职责 |
| --- | --- |
| `worldgen/` | 当前地图生成：`WorldgenLayout`（布局 v5）→ `WorldgenGeometry` 道路/地块切分 → `ThemedDistrict` / `WarehouseDistrict` / `SeededWarehouseDistrict` / `IndustrialYard` / `RescueCourt` 等街区类型，`Worldgen*` 地面/摆设/美术。新旅程固定使用 `WorldgenState.initial_build(seed, true, true)`（BH_LEVEL_V1 + 工业场）。 |
| `exploration/` | 探索行动（daily action v9）、站点/道具/目标、`ExplorationLayout` 导航与校验、`LevelSummary`。 |
| `rogue/` | `DailyActions` 行动派发（只剩 Exploration / Investigation 两条），以及仍被当前数据结构复用的旧行动/布局工具类（`TaskActions`、`WeaponActions`、`NeighborhoodLayout`、`WorldLayout` 等）。 |
| `campaign/` | 短流程战役规则 `CampaignRules/CampaignState`、调查日、事件出击、侦察、路障、广告牌、跨日压力。 |
| `expedition/` | 场内运行时：`Expedition` 及其职责 helper（见上）、角色/敌人、导航、巴士撤离 `BusJourney`、镜头、出击快照 `SortieSnapshot`（暂存/恢复）。 |
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
