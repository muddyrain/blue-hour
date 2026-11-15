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

营地玩家入口直接显示 `CampSceneWorld` 的旧渔协院落，不再隐藏世界后展示静态背景。`CampSceneLayout` 只定义营地表现坐标；`IsoSpace` / `IsoTiles` / `IsoBuildingArt` / `IsoAtlas` 与出征场共用，世界和设施标签共同等比缩放。三个设施位读取 `EconomyBuildV1.level()`（已有营地数据仍经 `CampFacilities` 读取）：未建为空地与材料，一级为小屋，二级换闭合屋顶建筑并补齐门前摆件。场景只发原有建设、补给、工坊、特长训练、名册和任务选择意图，不拥有交易或存档规则。装备台继续打开已有配装页，其中保留支援与构筑入口。

`CampSceneResident` 仅给当前存活名册成员播放 `SurvivorVisualV1` 的正式八向待机/行走；沿院内固定环线散步，在补给、工坊、规划室和篝火旁停留，不实例化战斗角色、不写入存档。`CampSceneScenery` 绘制原创围栏、篝火和家具，所有立体物按脚点 Y 排序；暖暮复用 `ExpeditionAtmosphere.tint_for()` 及径向暖色点光，色调与灯光限制在世界层。`CampSceneStyle` 将营地与既有面板调整为暖炭灰，保留原面板布局参数。

营地底色层级为 -20，低于共用 `IsoTiles` 的 -10；设施、家具与人物留在 0 层的 Y 排序节点。`CampSceneLayout.PATHS` 定义碎石院内的混凝土通道，`DRESSING` 定义避开设施、门前与人物环线的生活摆件；不参与碰撞、导航或存档。镜头使用等比缩放，归航摘要出现时给摘要让出空间。氛围标题订阅 `CampSceneWorld.atmosphere_changed`，外部调用 `set_dusk()` 也会同步更新；场内标签平时缩小淡显，鼠标悬停或键盘焦点时强调。

生成关先由 `WorldgenDensity` 补房，`WorldgenDressing.freeze` 冻结碰撞景物，再由 `ParcelScenery.fit` 补齐场地，最后只运行一次 `WorldgenDressing.enrich`。装饰先预留停车垫和车棚，再沿道路及门前步道两侧放小件；开阔草坪不按面积填充日用品。装饰仍受门口、步道、巴士与装卸场保留区约束，不新增交互或碰撞。

`HarborWarehouse` 是第二个手摆地点“海边町·北港仓库”（地点键 `north_harbor`）。从第 3 天起，普通 `airdrop` 装备回收和定期五金补给通过 `ExplorationActions.supply()` 投影到港口；带独立空间锚点的侦察、路障、稀有/事件、深入回收和终局保留原图。与 `SeasideTown` 一样保留原任务/地图收据 ID 和 `generated`，不改变 `offers()`、奖励或源站点名义时长。港口地形和搜刮绑定集中在 `harbor_warehouse.gd`；`TaskActions.site_point()` 同时供运行时及快照校验使用，避免只有画面搬了位置。`HarborPresentation` 负责闭合建筑与外部门口工位，`HarborGround` 负责码头岸线表现，仍共用 `FieldNavigation`、原刷怪/入夜、派工、登车与结算。港口仅五盏工作灯（暖色/冷白）参与场景光池，货柜不充当光源。

`StreetLayout` 只读取 `world_data.barriers_block_shots`（默认 true），不反向引用地点生成器，避免资源导入经存档校验链回到任务资源。港口将水岸障碍标为不挡弹，并把非导出的完整地形、作业绑定和边界加入快照兼容哈希；捕获仍要求暂停。成组货柜只分配一个工位，其余有碰撞但无标签，额外源站点使用南侧周转箱。`HarborGround` 以 10 Hz 重绘低透明度慢漂水纹，避开栈桥并服从世界夜色。集合属于移动命令，可在 ACTIVE / ENGINE / BOARDING 下达；发动、全员登车与归航条件保持原规则。

港口作业耗时局部乘 `HarborWarehouse.WORK_FACTOR = 1.5`（PROJECT_TEMP）：名义进度与源站点时长保持原值，推进速度变慢；货台基础 18 秒，仓储点基础 27–45 秒，再应用既有人物/构筑倍率。不改全局时钟、奖励、刷怪权重；倍率参与港口快照兼容性哈希。

港口 SVG 使用现有 `IsoAtlas` 的脚点/地图尺寸协议，由 `tools/make_harbor_art.py`（纯 Python 标准库）生成并登记 SHA；没有 AI 生成图像或第三方素材。`tests/harbor_warehouse.gd` 检查实际任务选择、布局可达、窄巷、水面、登车区域、源数据不变、作业耗时与部分作业快照重建，已纳入 `tools/godot.py check`。

### 存档说明

- 不再兼容旧存档：v1–v5 `RunSave` 升级、v5 迁移导入、旧位置 `user://saves/run.json` 保护都已删除。读到不认识的存档会被拒绝，需要开新旅程。
- 当前存档的校验仍是“新状态投影到旧校验器”的链式结构（`EnemyState → WeaponState → …`），收据日志仍做哈希校验。这一部分与当前存档格式耦合，未在本轮删除；后续可整体替换为简单的单文件 JSON 存档。

## 资源

- 场内五名幸存者：`SurvivorVisualV1` 读取 `assets/survivors_v1/{gu,xia,lin,shen,lu}.png`，每表 2048×2048 / 8×8 格。行按屏幕方向 E、SE、S、SW、W、NW、N、NE；列为待机 1 帧、走路 4 帧、攻击 3 帧。所有朝向直接绘制，不翻转。固定脚点 (128,224)，`ActorVisual.BODY_SCALE = 0.22`。`IsoSpace.attach_actor()` 标记画面投影，幸存者用投影后的朝向选择整帧；有瞄准意图时走路整帧随瞄准方向，避免身体与握持使用不同朝向。来源与生成规格见该目录 `generation.json`，切片注册由 `tools/build_survivor_atlas.py` 完成；敌人各自的方向与动作模块不变。
- 幸存者握持：`SurvivorWeaponRig` 的 5×8×8 原帧像素挂点驱动现有五种武器（卡宾、长管、霰弹、斧、锤），不增加身体或武器位图。原帧手部通过 `hand_occlusion.gdshader` 在握柄上重绘，头发层沿用原帧；背向三个朝向将整个握持节点放到身体后方，握点沿原帧袖口外缘校准；北向额外向持握侧外撇 15°，让枪身从肩侧露出，所有局部层仍留在角色的 Y 排序组。后坐同时移动身体、原手部和枪。近战通过 `CombatWeaponVisualV1` 读取 `CombatRuntime` 的蓄力/恢复阶段，命中当步显示接触帧与挥砍弧；重复 `present()` 不累积旋转，也不推进规则时钟。远程沿用 `show_fire()` 事件触发的 0.24 秒动作，枪口闪光仅前 0.06 秒；入夜后同位置有半径约 24 像素、能量最高 0.42 的短时暖光（PROJECT_TEMP 表现参数）。
- 弹道坐标边界：`aimed_shot_offset()` / `muzzle_offset()` 保留原三向挂点的地图空间弹道起点，供规则判墙、穿透和存档验证使用。`rendered_muzzle_offset()` 返回当前画面局部枪口；`ExpeditionFeedback._shot_trace()` 将已提交弹道接到这个枪口，并将命中平面的高度转换成直立看板高度。霰弹也复用此表现入口；不改变范围、伤害、冷却、弹量或墙体判定。
- 通用受击：`ActorVisual` 的原受击事件叠加保留原贴图/物种材质的弱暖色提亮与衰减位移：底层始终不透明，叠加层峰值 alpha 0.20、RGB 增益不超过 1.5，0.18 秒内平方衰减，逻辑脚点不动。三种基础感染者直接复用原来的四帧倒地，仍在原 0.95 秒尸体生命周期内短停后淡出，倒地保持原夜间补偿并用中性 0.90 明度代替额外偏蓝压暗；幸存者沿用 m5 倒地图并短时落定，保留可见直至原流程移除。新效果不增加存档字段，不修改特殊感染者的图或动作模块。
- 三种基础感染者由 `NormalInfectedV1`、`RushInfectedV1`、`HeavyInfectedV1` 独立展示，`ActorVisual._pose_body()` 按敌人类型接线；特殊种继续走各自模块。每种有 e/se/s/ne/n 五个源朝向，西侧三个朝向镜像；每向 4×4 格，0 待机、1–6 步态、7–9 攻击接触/跟进/恢复、10–11 受击、12–15 倒地。普通种保留原 1254×1254 源表；冲刺/重型为 1280×1280、320 方格，统一脚点 (160,304)，生成提示见 `assets/infected_v1/PROMPTS.md`。
- `InfectedSheetV1` 只共用切帧、固定脚点、事件时序与 `infected_palette` 灰绿低饱和材质。步态沿用已有位移时钟：普通/冲刺 8 fps、重型 6 fps，再乘实际速度/34；冲刺状态也播放完整步态。攻击仍由既有 0.30 秒事件驱动，重型蓄势使用恢复支撑姿态，不改变伤害/移动/存档规则。独立显示比例为普通 0.26、冲刺 0.29、重型 0.34，经 `ActorVisual.field_scale()` 换算，幸存者比例不变（均为 PROJECT_TEMP 表现数值）。
- 特殊感染者：`ScreamerVisualV1`、`ToxicCarrierVisualV1`、`BurstInfectedVisualV1`、`NightHoundVisualV1`、`BreacherVisualV1` 分别读取 `assets/infected_v1/{screamer,toxic,burst,hound,breacher}/actions.png`。每表 1280×3072，5 列 e/se/s/ne/n、12 行（待机、四帧步态、两段蓄势、释放、恢复、受击、倒地、伏地），西侧三向镜像；格 256×256，脚点 (128,240)。`SpecialInfectedSheetV1` 统一注册并复用基础种 palette，入夜参数仍逐 Sprite 设置。生成提示、来源 SHA 和登记参数见 `special_prompts.json` / `special_generation.json`，构建工具为 `tools/build_special_infected_atlas.py`。
- `SpecialInfectedFeedback` 是 `ExpeditionFeedback` 持有的只读表现节点，随 UI/光照刷新读取现有 burst、toxic、hound、encounter/pump 状态；没有技能计时器或存档字段。Boss 仅将 `ActorVisual.enemy_kind` 设为 `breacher_v1`，规则与快照仍为历史 heavy 种类；替代抽水站临时肩架。危险边界经 `InfectedDangerGeometry` 将规则地图圆投影到等距场景，毒云、爆囊、夜犬与 Boss 预警采用不受夜间灯光压暗的材质。抽水站冲锋道同样只投影原锁定矩形，不改判定。尖啸声波表示呼援，不是伤害圈。
- 入夜表现：`ExpeditionAtmosphere` 保留白天 → 暖黄昏 → 蓝时 → 深夜 `(0.24, 0.28, 0.48)` 的世界色与有上限的暖灯/橱窗光，每次刷新同时向现存角色传入昼夜量（含新刷出的敌人和破阵者）。`ActorVisual` 只在 `amount > 0.45` 后平滑补偿角色及原有脚环，深夜 RGB 增益上限 `(1.5, 1.5, 1.25)`，不改变世界地面或动作；基础种及五种特殊种通过每 Sprite 的 `night_readability` 参数把 palette 亮度系数从白天 `0.72` 放宽到深夜 `1.0`，不修改共享材质状态。特殊动作表另设实例参数 `special_night_lift`：按原图亮度放宽夜间中间调，指数 `0.35`（夜犬 `0.45`），额外增益上限 `1.65`，白天增益严格为 `1`；三种基础表不启用。爆囊的 `burst_sac_contrast` 只选择原图暖色囊块，保留其明暗塑形并改为较亮的低饱和暖黄绿，衣服和皮肤继续走 82% 灰绿混色。动作、受击、倒地均保留实例参数。`NightLighting` 暗角夜间系数为 `0.40`（总遮盖上限 `0.435`），避免 HUD 下的暗角再次抹掉角色和暖灯细节。这些均为 PROJECT_TEMP 表现数值。

- `assets/`：运行时美术/音频。逐文件来源与 SHA 登记在 `assets/PROVENANCE.json`，`tools/validate_assets.py` 校验（`check` 会运行）。
- 美术为项目原创：AI 辅助生成的 PNG（统一透明裁切、等比缩放、登记脚点后入图集，见各目录 `atlas.json`/`manifest.json`）、手绘 SVG、代码绘制；音效由 `src/features/audio_settings/generate_cues.py` 数学合成。生图提示要点在 `assets/world_v1/source/PROMPTS.md`、`assets/world_v2/source/prompts.md`。
- 不使用 Deadly Days 的任何图像、声音或录屏。

音效沿用应用持有的 `B1AudioService`，没有 Autoload 或全局 AudioServer 总线写入。`ExpeditionFeedback` 通过 `audio_cue_requested` 上报开火（含霰弹）、近战提交、统一命中、特殊种蓄势和入夜；`AppSortie` 把意图接回已有服务，搜刮/发动与营地、任务选择、声音设置的 UI 确认仍走原回调。毒气和夜犬读取现有蓄势边沿，重复刷新不重播；暂停恢复快照只记录已存在的提示状态。巴士演出单独发登车/驶离提示，在结算冻结、战斗事件断开后继续接入同一服务。

音量默认仍为主音量 0.8、世界 0.75、UI 0.7、非静音。静音/分类归零立即停止对应尾音并拒绝新声音；世界暂停冻结现有声流、拒绝新请求，UI 保持可用，恢复不补播。服务固定 6 个世界与 2 个 UI 声部，其中世界的 2 个优先留给搜刮、巴士和预警；重要提示可替换较低优先级声音，满载不排队。15 个 WAV 为纯 Python 标准库数学合成（Codex 辅助代码、没有 AI 音频模型或采样素材），每个峰值 0.55，`VOICE_GAIN = 0.20`（PROJECT_TEMP 表现参数，原 0.16）；8 声部满滑杆的离散峰值和不超过 0.88。`tests/audio_feedback.gd` 已纳入 `check`；`python tests/test_audio_assets.py` 可脱离引擎校验生成可复现性、注册、来源与混音余量。

## 测试与工具

- `tools/godot.py check`：导入、启动（`BH_READY`）与 `tests/` 下的单元/契约测试，任何 `SCRIPT ERROR`/`ERROR` 或 `"failures": N>0` 都判失败。
- `tests/smoke_loop.gd`（在 `check` 中）：无头跑完整一局：新档 → 出击 → 搜刮 → 战斗 → 巴士撤离 → 结算 → 重启读档 → 第二次出击；任何 SCRIPT ERROR 都会判失败。
- `persona_ui` 在 main 上就已失败（1024×640 营地详情滚动高度 <140px），属已知问题。
- 其他 `tools/*_flow.py` 是历史上针对单个系统的流程脚本，未纳入 `check`，部分在 main 上已经失效，后续可继续清理。
