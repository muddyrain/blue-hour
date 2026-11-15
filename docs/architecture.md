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

生成关先由 `WorldgenDensity` 补房，`WorldgenDressing.freeze` 冻结碰撞景物，再由 `ParcelScenery.fit` 补齐场地，最后只运行一次 `WorldgenDressing.enrich`。装饰先预留停车垫和车棚，再沿道路及门前步道两侧放小件；开阔草坪不按面积填充日用品。装饰仍受门口、步道、巴士与装卸场保留区约束，不新增交互或碰撞。

### 存档说明

- 不再兼容旧存档：v1–v5 `RunSave` 升级、v5 迁移导入、旧位置 `user://saves/run.json` 保护都已删除。读到不认识的存档会被拒绝，需要开新旅程。
- 当前存档的校验仍是“新状态投影到旧校验器”的链式结构（`EnemyState → WeaponState → …`），收据日志仍做哈希校验。这一部分与当前存档格式耦合，未在本轮删除；后续可整体替换为简单的单文件 JSON 存档。

## 资源

- 场内五名幸存者：`SurvivorVisualV1` 读取 `assets/survivors_v1/{gu,xia,lin,shen,lu}.png`，每表 2048×2048 / 8×8 格。行按屏幕方向 E、SE、S、SW、W、NW、N、NE；列为待机 1 帧、走路 4 帧、攻击 3 帧。所有朝向直接绘制，不翻转。固定脚点 (128,224)，`ActorVisual.BODY_SCALE = 0.22`。全身帧替代幸存者旧的静态上身/程序手臂叠层；头部仅保留同帧、同变换的遮挡层，保证枪械仍在头发后方。枪械、枪口和弹道预测继续使用原有握点与时钟。开火事件触发表现模块内 0.24 秒的准备/出招/回收，受击与倒地沿用 m5 全身图。来源与生成规格见该目录 `generation.json`，切片注册由 `tools/build_survivor_atlas.py` 完成；敌人展示仍走各自原有模块。
- 三种基础感染者由 `NormalInfectedV1`、`RushInfectedV1`、`HeavyInfectedV1` 独立展示，`ActorVisual._pose_body()` 按敌人类型接线；特殊种继续走各自模块。每种有 e/se/s/ne/n 五个源朝向，西侧三个朝向镜像；每向 4×4 格，0 待机、1–6 步态、7–9 攻击接触/跟进/恢复、10–11 受击、12–15 倒地。普通种保留原 1254×1254 源表；冲刺/重型为 1280×1280、320 方格，统一脚点 (160,304)，生成提示见 `assets/infected_v1/PROMPTS.md`。
- `InfectedSheetV1` 只共用切帧、固定脚点、事件时序与 `infected_palette` 灰绿低饱和材质。步态沿用已有位移时钟：普通/冲刺 8 fps、重型 6 fps，再乘实际速度/34；冲刺状态也播放完整步态。攻击仍由既有 0.30 秒事件驱动，重型蓄势使用恢复支撑姿态，不改变伤害/移动/存档规则。独立显示比例为普通 0.26、冲刺 0.29、重型 0.34，经 `ActorVisual.field_scale()` 换算，幸存者比例不变（均为 PROJECT_TEMP 表现数值）。
- 特殊感染者：`ScreamerVisualV1`、`ToxicCarrierVisualV1`、`BurstInfectedVisualV1`、`NightHoundVisualV1`、`BreacherVisualV1` 分别读取 `assets/infected_v1/{screamer,toxic,burst,hound,breacher}/actions.png`。每表 1280×3072，5 列 e/se/s/ne/n、12 行（待机、四帧步态、两段蓄势、释放、恢复、受击、倒地、伏地），西侧三向镜像；格 256×256，脚点 (128,240)。`SpecialInfectedSheetV1` 统一注册并复用基础种 palette，入夜参数仍逐 Sprite 设置。生成提示、来源 SHA 和登记参数见 `special_prompts.json` / `special_generation.json`，构建工具为 `tools/build_special_infected_atlas.py`。
- `SpecialInfectedFeedback` 是 `ExpeditionFeedback` 持有的只读表现节点，随 UI/光照刷新读取现有 burst、toxic、hound、encounter/pump 状态；没有技能计时器或存档字段。Boss 仅将 `ActorVisual.enemy_kind` 设为 `breacher_v1`，规则与快照仍为历史 heavy 种类；替代抽水站临时肩架。危险边界经 `InfectedDangerGeometry` 将规则地图圆投影到等距场景，毒云、爆囊、夜犬与 Boss 预警采用不受夜间灯光压暗的材质。抽水站冲锋道同样只投影原锁定矩形，不改判定。尖啸声波表示呼援，不是伤害圈。
- 入夜表现：`ExpeditionAtmosphere` 保留白天 → 暖黄昏 → 蓝时 → 深夜 `(0.24, 0.28, 0.48)` 的世界色与有上限的暖灯/橱窗光，每次刷新同时向现存角色传入昼夜量（含新刷出的敌人和破阵者）。`ActorVisual` 只在 `amount > 0.45` 后平滑补偿角色及原有脚环，深夜 RGB 增益上限 `(1.5, 1.5, 1.25)`，不改变世界地面或动作；基础种及五种特殊种通过每 Sprite 的 `night_readability` 参数把 palette 亮度系数从白天 `0.72` 放宽到深夜 `1.0`，不修改共享材质状态。特殊动作表另设实例参数 `special_night_lift`：按原图亮度放宽夜间中间调，指数 `0.35`（夜犬 `0.45`），额外增益上限 `1.65`，白天增益严格为 `1`；三种基础表不启用。爆囊的 `burst_sac_contrast` 只选择原图暖色囊块，保留其明暗塑形并改为较亮的低饱和暖黄绿，衣服和皮肤继续走 82% 灰绿混色。动作、受击、倒地均保留实例参数。`NightLighting` 暗角夜间系数为 `0.40`（总遮盖上限 `0.435`），避免 HUD 下的暗角再次抹掉角色和暖灯细节。这些均为 PROJECT_TEMP 表现数值。

- `assets/`：运行时美术/音频。逐文件来源与 SHA 登记在 `assets/PROVENANCE.json`，`tools/validate_assets.py` 校验（`check` 会运行）。
- 美术为项目原创：AI 辅助生成的 PNG（统一透明裁切、等比缩放、登记脚点后入图集，见各目录 `atlas.json`/`manifest.json`）、手绘 SVG、代码绘制；音效由 `src/features/audio_settings/generate_cues.py` 数学合成。生图提示要点在 `assets/world_v1/source/PROMPTS.md`、`assets/world_v2/source/prompts.md`。
- 不使用 Deadly Days 的任何图像、声音或录屏。

## 测试与工具

- `tools/godot.py check`：导入、启动（`BH_READY`）与 `tests/` 下的单元/契约测试，任何 `SCRIPT ERROR`/`ERROR` 或 `"failures": N>0` 都判失败。
- `tests/smoke_loop.gd`（在 `check` 中）：无头跑完整一局：新档 → 出击 → 搜刮 → 战斗 → 巴士撤离 → 结算 → 重启读档 → 第二次出击；任何 SCRIPT ERROR 都会判失败。
- `persona_ui` 在 main 上就已失败（1024×640 营地详情滚动高度 <140px），属已知问题。
- 其他 `tools/*_flow.py` 是历史上针对单个系统的流程脚本，未纳入 `check`，部分在 main 上已经失效，后续可继续清理。
