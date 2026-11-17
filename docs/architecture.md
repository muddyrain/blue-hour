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

`IsoAtlas.stamp_cell()` 只用于地面：共享不透明菱形多边形边界，缓存去 alpha 的地面纹理，UV 向内避开源图的透明平滑边缘。建筑和人物仍使用原贴图路径。`tools/make_iso_art.py` 的 `export_street_tiles()` 生成无逐格定向渐变、十字缝和亮水纹的现有街道贴图；道路中线保留，`IsoTiles` 用局部哈希放置稀疏低对比短水纹，不消耗模拟随机数。`tools/make_iso_buildings.py` 的屋顶面保留明暗和外轮廓，不画交叉瓦格；石桥、墙体仍可使用有限砖缝。

`tests/ground_seams.gd` 在原生渲染中取样 1024 与 1600 两种宽度，并以原透明包围盒绘制作为反例，防止地面覆盖接缝回归。`tests/surface_lines.gd` 另检查源图，并在正式海边町的 1024×576 / 1600×900 画面中检查绿屋顶、坡屋顶、运河、路面、人行道的局部高对比线像素，以及草地沿 32 单位周期的相位均值，避免把自然草叶斑驳误判成网格。反例在同一正式画面上重加菱形线，验证检测灵敏度。无头模式明确跳过像素检查，需用原生 `gl_compatibility` 运行这两个测试；不改正式裁切、镜头缩放或图层透明度来通过测试。

营地玩家入口直接显示 `CampSceneWorld` 的旧渔协院落，不再隐藏世界后展示静态背景。`CampSceneLayout` 只定义营地表现坐标；`IsoSpace` / `IsoTiles` / `IsoBuildingArt` / `IsoAtlas` 与出征场共用，世界和设施标签共同等比缩放。三个设施位读取 `EconomyBuildV1.level()`（已有营地数据仍经 `CampFacilities` 读取）：未建为空地与材料，一级为小屋，二级换闭合屋顶建筑并补齐门前摆件。场景只发原有建设、补给、工坊、特长训练、名册和任务选择意图，不拥有交易或存档规则。装备台继续打开已有配装页，其中保留支援与构筑入口。

`CampSceneResident` 仅给当前存活名册成员播放 `SurvivorVisualV1` 的正式八向待机/行走；沿院内固定环线散步，在补给、工坊、规划室和篝火旁停留，不实例化战斗角色、不写入存档。`CampSceneScenery` 绘制原创围栏、篝火和家具，所有立体物按脚点 Y 排序；暖暮复用 `ExpeditionAtmosphere.tint_for()` 及径向暖色点光，色调与灯光限制在世界层。`CampSceneStyle` 复用 `CampStyle` 的冷蓝方角主题，保留既有面板布局参数和语义状态色；营地队员栏的 HP 与行动资格仍来自真实快照。场景素材与光照独立于 UI 配色。

成长沿现有 `CampEdit` / `FrozenSettlement` → `RunTransaction` 链路保存。`EconomyBuildV1` 三个设施键 `supply` / `workshop` / `planning` 独立建设、最高二级：补给成功归航应发 2/3 粮；工坊回营自动修复最多 1/2 件出发前损坏的闲置武器，维修减免 4/6 币，下次出击换弹耗时乘 0.95/0.90；规划室成功归航给合格队员中的最低特性等级者增加 1/2 点进度。自动收益读取出发前状态，建设不会追溯补发；补给受库存容量限制，规划室不选择未登记、阵亡或特性满级者。

枪械强化复用 `upgrade_weapon` 交易，初始枪、回收枪及自制枪均可升至五级；一级工坊开放二、三级，二级开放四、五级。实例 ID、品质、词条和弹匣保留，直伤沿用每级增加基础值 10% 的规则。来源校验先从第一次实例编辑的前态或冻结掉落重建来源，再按经济编辑历史重放，旧规则校验只读取来源投影，不保存第二套武器。工坊换弹倍率取 `field_departure`，在 `ExpeditionSupport.apply_build()` 与个人特质、道具倍率各乘一次；`SortieSnapshot` 的校验和兼容哈希使用同一倍率。营地配装预览、档案与场内卡片显示一致的有效换弹时间。

人物经验每次个人击退记 10，存活归航后生效；等级提高时生命上限每级增加 5，并恢复新增生命。特性独立使用 `TraitRules` 的五级阈值，射击间隔、搜刮耗时、移速由现有场内接线生效；篝火训练每 1 粮增加 1 点个人特性进度。档案与悬停卡说明成长来源及具体效果，训练预览同时列出前后效果；结算显示生命上限变化、特性变化和设施回营收益。`tests/progression_contracts.gd` 验证实际弹匣与工作进度，`tests/progression_save.gd` 在 `.local/` 定向验证冻结结算、设施/武器/训练交易、独立读档及下次出击/快照重建，不作为正常玩家路线的完成证明。

营地底色层级为 -20，低于共用 `IsoTiles` 的 -10；设施、家具与人物留在 0 层的 Y 排序节点。`CampSceneLayout.PATHS` 定义碎石院内的混凝土通道，`DRESSING` 定义避开设施、门前与人物环线的生活摆件；不参与碰撞、导航或存档。镜头使用等比缩放，归航摘要出现时给摘要让出空间。氛围标题订阅 `CampSceneWorld.atmosphere_changed`，外部调用 `set_dusk()` 也会同步更新；场内标签平时缩小淡显，鼠标悬停或键盘焦点时强调。

生成关先由 `WorldgenDensity` 补房，`WorldgenDressing.freeze` 冻结碰撞景物，再由 `ParcelScenery.fit` 补齐场地。`ExplorationLayout.complete` 在门口路线与道具拟合前先拒绝已被挡住的街区必经通道，放置道具后仍保留最终通道校验；全部几何校验通过后才运行一次无碰撞的 `WorldgenDressing.enrich`，随后计算地图指纹。装饰先预留停车垫和车棚，再沿道路及门前步道两侧放小件；开阔草坪不按面积填充日用品。装饰仍受门口、步道、巴士与装卸场保留区约束，不新增交互或碰撞。

`FieldNavigation` 为每张图缓存最多 2048 组精确起终点的原始 AStar 路径（含不可达结果），供任务证书和卡片摘要复用；不改变择路规则。网格重建或临时路障变更会清空缓存，返回数组独立复制，私有路障图不共享路径状态。

大图跳点搜索由 `FieldRouteSearch` 显式调用 `native/route_kernel.c` 的 `RefCounted` 实例。碰撞矩形仍按同一半开栅格覆盖与外圈构成 solid mask；原生 helper 在线性预处理内建立四向直线强制后继、四向对角静态终点和行/列连通段。每次查询将目标与这些段相交，得到与 Godot 4.7.2 `_jump` 完全相同的后继；邻居顺序、float32 octile 评分、相等评分时的堆操作及起点后处理保持原样，返回完整原始路径，不以距离场替代路径。小图继续使用原生非跳点 AStarGrid2D。索引随地图或私有路障变更销毁，查询仍持有原互斥锁；没有增加路线缓存容量或工作线程。`tests/support/navigation_oracle.gd` 保留 c65fa3a 的完整实现，仅供 `navigation_routes` 对照完整点序列与精确累计距离。构建入口 `tools/build_navigation.py` 使用锁定引擎导出的公开 GDExtension 接口头与 API 元数据，校验公开内建类型的 opaque buffer 大小，String/StringName/PackedInt32Array 全部通过公开构造/析构 API 管理，不依赖全零空字符串表示；GCC/Clang 开启严格单精度运算、禁止 FMA 收缩/fast-math。支持 Linux x86_64、MinGW/LLVM-MinGW Windows x86_64 交叉或本机构建，以及使用现有 Apple SDK 的 macOS arm64/x86_64 构建（最低 macOS 11.0）；Mac `universal` 目标用 `lipo` 合并并核对两个 slice。SDK/编译器/参数和输出 SHA 纳入缓存身份，thin 重建或失败使旧 universal 库失效。输出仅在 `.local/navigation-native/`，不依赖引擎私有对象布局、私有符号或进程扫描。算法顺序绑定 4.7.2；升级引擎必须重建并重跑完整点序列对照。

`FieldRouteKernelLoader` 在主线程启动阶段显式尝试一次可选加载，工作线程开始读档前完成类注册；`FieldRouteSearch` 以互斥锁共享加载状态，网格仍各自持有内核实例。清单存为普通 `.cfg`，避免编辑器自动扫描 `.gdextension` 在缺库时出错；运行时先按官方平台特征匹配、检查文件，再于 `user://navigation-native/` 写入供公开 `GDExtensionManager.load_extension()` 使用的描述文件。缺清单、无匹配平台、缺库、不能写描述文件、加载失败或内核配置失败，都回到同一网格的 `AStarGrid2D.get_point_path()`，沿用原起点后处理、缓存、完整地图/选卡/历史校验，不引入第二套规则。`BH_NAVIGATION` 标记可观察实际后端，`tests/navigation_fallback.gd` 在独立进程覆盖失败场景及完整路径等价；`tools/test_navigation_build.py` 覆盖可选构建、失败清理和平台键。

已启用 `native/export_plugin.gd` 的 `EditorExportPlugin`，通过公开 `add_file` / `add_shared_object` 将清单和已有目标库加入普通导出。Linux/Windows 导出库位于可执行文件旁；macOS 库位于 `.app/Contents/Frameworks`，运行时按实际可执行文件的 `../Frameworks` 定位，支持整体移动。macOS 通用导出只选择 fat dylib，并将包内两个架构的清单条目改为同一文件；thin 导出仍选择对应架构库。没有目标库时照常导出并明确报告严格回退。`tools/godot.py run/check/export` 不触发编译，玩家无工具链依赖；`export --templates` 将指定版本模板复制到隔离配置；Mac 使用隔离 HOME 的 `Library/Application Support/Godot/export_templates`。`macOS` 预设使用通用官方模板和内置 ad-hoc 签名；不做 Apple 公证或发布。库缺失只影响性能，不能宣称因此满足 Windows 大存档读档耗时要求。

导航网格构建按膨胀后的障碍矩形覆盖栅格，仅在边缘逐格核对角色的世界边界，不再对每格遍历全部障碍；AStar 参数、障碍膨胀尺寸及最终 solid mask 保持一致。`tests/navigation_cache.gd` 将每格及完整路径与原逐格判定比较，覆盖重叠、退化、偏移和非整格边界，并用查询次数限制重复工作，不依赖机器耗时阈值。

`WorldgenDensity` 在每次补房调用内只投影一次既有建筑外形、门点和围栏；每个地块再按扩大 64 单位的范围保守筛选障碍，保留配对关系与原顺序。原 `_fits` 最远查询仅越出地块 36 单位，最终判定公式不变；新增建筑立即追加到局部及全局投影，后续地块能看到此前新增结果。变体计算在补房序号变化时失效。`WorldgenDressing` 在单次装饰生成中按地块预投影门点和外形矩形，复用原距离、道路边缘与短路判定。两类预计算均不跨调用保存，不改变随机调用或生成结果。`worldgen_contracts` 检查原完整指纹与投影次数；`worldgen_density`、`worldgen_dressing` 使用冻结的旧算法比较完整输出，覆盖范围边界、配对传播、候选顺序和重复调用，并接入公开 `check`。

`ExplorationLayout` 将最多 48 份完整几何证明与原生导航图分开保存，大地图原生图仍最多保留 4 份。淘汰导航图时保留已认证的完整布局及门点距离；再次查询只从同一布局重建相同网格，不重复生成地图和全量路线证明。两类缓存都由完整布局指纹绑定，并在同一互斥锁下发布；48 份证明按最早入库顺序逐份淘汰，随证明删除对应布局和导航图。`worldgen_contracts` 强制淘汰原生图后核对重建次数、全部门点路径和篡改拒绝。


`HarborWarehouse` 是第二个手摆地点“海边町·北港仓库”（地点键 `north_harbor`）。从第 3 天起，普通 `airdrop` 装备回收和定期五金补给通过 `ExplorationActions.supply()` 投影到港口；带独立空间锚点的侦察、路障、稀有/事件、深入回收和终局保留原图。与 `SeasideTown` 一样保留原任务/地图收据 ID 和 `generated`，不改变 `offers()`、奖励或源站点名义时长。港口地形和搜刮绑定集中在 `harbor_warehouse.gd`；`TaskActions.site_point()` 同时供运行时及快照校验使用，避免只有画面搬了位置。`HarborPresentation` 负责闭合建筑与外部门口工位，`HarborGround` 负责码头岸线表现，仍共用 `FieldNavigation`、原刷怪/入夜、派工、登车与结算。港口仅五盏工作灯（暖色/冷白）参与场景光池，货柜不充当光源。

`StreetLayout` 只读取 `world_data.barriers_block_shots`（默认 true），不反向引用地点生成器，避免资源导入经存档校验链回到任务资源。港口将水岸障碍标为不挡弹，并把非导出的完整地形、作业绑定和边界加入快照兼容哈希；捕获仍要求暂停。成组货柜只分配一个工位，其余有碰撞但无标签，额外源站点使用南侧周转箱。`HarborGround` 以 10 Hz 重绘低透明度慢漂水纹，避开栈桥并服从世界夜色。集合属于移动命令，可在 ACTIVE / ENGINE / BOARDING 下达；发动、全员登车与归航条件保持原规则。

港口作业耗时局部乘 `HarborWarehouse.WORK_FACTOR = 1.5`（PROJECT_TEMP）：名义进度与源站点时长保持原值，推进速度变慢；货台基础 18 秒，仓储点基础 27–45 秒，再应用既有人物/构筑倍率。不改全局时钟、奖励、刷怪权重；倍率参与港口快照兼容性哈希。

港口 SVG 使用现有 `IsoAtlas` 的脚点/地图尺寸协议，由 `tools/make_harbor_art.py`（纯 Python 标准库）生成并登记 SHA；没有 AI 生成图像或第三方素材。`tests/harbor_warehouse.gd` 检查实际任务选择、布局可达、窄巷、水面、登车区域、源数据不变、作业耗时与部分作业快照重建，已纳入 `tools/godot.py check`。

`CapeStation` 是手摆地点“海边町·岬角车站”（`cape_station`）。第 4 天起的偶数日，普通 `supply` 食品任务在 `ExplorationActions.supply()` 投影到车站；带独立空间锚点的任务保留原图。源 `generated`、任务/地图 ID、收益和名义工时保持原值，`TaskActions.site_point()` 与 `outdoor_site()` 同时供运行时及回放读取车站屋外工位。站房、商店、民居封闭，短轨阻挡通行但不挡弹，低站台两端可绕行。`StationPresentation` 绑定搜刮点，`StationGround` 展示轨道与低站台，共用导航、派工、支援、刷怪与巴士流程；完整地形加入快照兼容哈希。8 个原创 SVG 由 `tools/make_station_art.py` 复用港口绘图原语生成并登记来源，不修改港口地形。

`SortieEvents` 只投影现有事件：`EventSortieV1` 的临时物资点保留现场二选一、开工警报和 `task_event` 结算；`RareSortie` 的断电冷库关闭两处食品站点的窗光，保留路灯和车灯，并从 `site_facts` 展示近处/远端搜集结果。提示持续显示在场内，状态均从原收据重建，不新增事件存档格式，也不重新抽选。既有种子选择器、概率与奖励保持不变。

`CampaignPressureV1.blockade_night()` 在启用跨日压力的普通第 4、7、10…天出击预告“封锁夜”（调查、稀有、事件、终局除外）。入夜后普通敌种抽签按 actor ID 模 3，把其中两类普通槽分别升级为重压、疾奔，其余槽与特殊种优先级沿用原规则；`CombatEnemyRules.pick_for()` 同供刷怪与回放证明使用。任务卡、顶部时钟、黄昏和入夜均有提示，结算从原收据的任务日期及经过时间还原是否经历封锁夜。上限、间隔、出入口、安全距离和 `ExpeditionAtmosphere` 曲线不变；策略参数进入快照哈希。`tests/maps_events.gd` 覆盖车站正式选卡、导航/屋外作业/登车/恢复与封锁夜来源校验；`tests/sortie_events.gd` 覆盖事件两分支、冷库断电与结算事实，两者均纳入 `check`。

场内普通增援以 `ExpeditionTuning.spawn_seconds = 10` 为基准，`ThreatRules` 按原 70/105/140 秒边界给出 10/8/6/4.5 秒间隔（PROJECT_TEMP）；`CampaignPressureV1` 的 1.0/0.9/0.8 倍率仍只乘一次，封锁夜敌种替换不变。白昼保持 105 秒，`LevelSummary` 和任务卡证据不受此调整影响。开局 4 粮只增加一餐两人缓冲，不改任务、设施或训练收入。

`ExpeditionUi` 在短通知结束后投影当前撤离阶段、等待名单和口粮预估；B 保留先发动、后集合的接线，搜集者仍完成作业后归队。`ReturnFeedback.forecast()` 复用 `FieldJoinRules.meal_members()`、`CampFacilities.offered_food()` 和 `CampEconomy.post_battle_food()`：只读出发前设施、当前存活者、携带食物和库存上限，新同行首餐豁免，不发放收益。`ReturnFeedback` 同供冻结结算展示归航人数、场内阵亡、未登车及餐后饥饿死亡；终局标题按实际原因区分。

`C1ExpeditionHud.place_status_hint()` 先确定可用文本宽度，再按字体行高、行距和面板内边距计算最多两行的最小高度。裁切 Label 的固有最小尺寸可能仍为 1×1，布局使用显式计算的组合最小尺寸，避免反过来用这个固有值把底板锁在 28px。常驻提示第一行为撤离操作，第二行为口粮；过长的名单省略显示，完整文本与事件上下文保留在 tooltip。`tests/run_feel.gd` 在正式 Expedition 布局验证两种分辨率；原生渲染执行还对每行文字像素及无文字对照取样，无头 Dummy 执行会明确跳过像素取样。

### 存档说明

- `InvestigationActions` 将完整三槽选卡的紧凑指纹证明（最多 128 份）与 8 份 UI 完整描述分开保留；证明仍绑定整个营地的 `RecordEncoding.fingerprint`，只在三个槽位全部生成成功后发布，不依赖磁盘标记，也不改变选卡指纹。`ExplorationActions.level_map` 使用进程内 `ActionGenerationMemo`（最多 64 份、16 MiB 输入/结果原生序列化体积），按完整来源、显式生成参数、布局/探索策略与导航尺寸的内容哈希索引，并再次比较完整输入。相同来源的并发调用共用一项计算，调用者只拿独立副本；成功和失败尝试的诊断均保留。缓存不包含跨收据授权，哈希链接、事务次序及历史规则仍由日志逐条检查。

- `ReceiptJournal` 在物理读取和目录检查之后，对至少 12 条尚未证明的收据使用 `ReceiptValidation`，将完整解码/来源校验分为最多 3 个连续段并行执行（调用线程也承担一段）。首条先同步拒绝损坏根；全部任务结束后仍按原顺序执行每条哈希链接、跨收据规则和重放，成功前不发布前缀证明。已证明前缀和短增量仍沿原串行路径。工作线程不读写存档文件；共享纯结果经既有互斥锁发布，扩展人物种子缓存也经 `ActionMemo` 访问。`m48_record_cache` 覆盖完整 69 条历史的结果一致性、工作量上界及重哈希中间收据的拒绝。

- 不再兼容旧存档：v1–v5 `RunSave` 升级、v5 迁移导入、旧位置 `user://saves/run.json` 保护都已删除。读到不认识的存档会被拒绝，需要开新旅程。
- 当前存档的校验仍是“新状态投影到旧校验器”的链式结构（`EnemyState → WeaponState → …`），收据日志仍做哈希校验。这一部分与当前存档格式耦合，未在本轮删除；后续可整体替换为简单的单文件 JSON 存档。
- `EconomyBuildV1.source_action()` 的紧凑来源认证原始压缩字节与 ExactJSON，并通过重压缩核对完整 GZIP 流；比较仅兼容锁定 zlib 的 OS 头标记 3（Unix）、10（Windows）、19（macOS），其余头、DEFLATE、CRC/ISIZE 和尾随内容保持精确比较。写入格式与已有字节不变，避免把写入平台的元数据误当作来源内容差异。

## 小队与救援

`RosterState.MAX_LIVING = 8`、`MAX_HISTORY = 10`，开局仍由 `SurvivorRoster.new_crew()` 创建两人。`RescuePoolState` 继续决定唯一冻结候选，`RescueTarget` 接近后援救 10 秒，经原 `field_join_gate` 的持久化确认提升同一个 NPC，接入现有战斗、派工、成长、登车和结算；成功归航登记，同行中阵亡则写入永久历史。原三名候选优先，耗尽后选 crew_6–8；登记过八人后，空编可救 crew_9 程见川或 crew_10 许映禾。后备是不同身份，分别复用何清晏、阮疏影外观，不复活死者。有限候选全部登记后明确提示耗尽。

任务卡与援救目标展示冻结候选姓名；未接纳者不开放队员详情。救援标记、进度与标签使用 `IsoSpace` 投影，规则坐标和任务收据不变。`SquadDeployment` 共用原额外出生点搜索，供运行时、侦察证据与广告牌作业证据重建使用，不扩写源地图的 arrivals。原五人 `SurvivorPersona` 事实与 policy 保持原字节结构，以保留既有 offers 指纹；第 6–10 人按同一种子排序继续生成，按种子缓存、按身份读取，不增加存档字段或迁移分支。容量校验同步覆盖训练、特性、配装、治疗、能力、敌人目标、Boss 命中名单与快照；现行 EnemyState schema 111 无需改变。

正式头像、名册与出发复核共用 `PersonaCard.hover_text()` / `camp_hover()`，读取既有 `PersonaViewModel` 的姓名、生命、等级、实际武器与特性；复核 Label 显式接收鼠标悬停；四处悬停共用有实底、自动换行的信息卡，避免长说明溢出或被底层 HUD 干扰。`tests/squad_recruit.gd` 按稳定成员 ID 检查全部八人，并在原生渲染时检查第八张头像的真实 tooltip；救援覆盖满编拒绝、减员后的后备路径、接纳与冻结归航结果。`tests/squad_long_run.gd` 使用通过现有存档校验的定向八人夹具，运行第 8/10 天正式车站关的自然时钟、AI、寻路、夜间登车与冻结结算；其中第 10 天另加一例明确的定向阵亡输入，不代表人工通关或自然伤亡。夜间暂停同时校验完整 `SortieSnapshot` 并拒绝篡改的增援间隔；快照威胁重建读取 `ExpeditionTuning`，与现场使用同一白昼长度和增援基准。

## 资源

- 场内八套幸存者外观：`SurvivorVisualV1` 读取 `assets/survivors_v1/{gu,xia,lin,shen,lu,ruan,ye,he}.png`，每表 2048×2048 / 8×8 格。行按屏幕方向 E、SE、S、SW、W、NW、N、NE；列为待机 1 帧、走路 4 帧、攻击 3 帧。所有朝向直接绘制，不翻转。固定脚点 (128,224)，`ActorVisual.BODY_SCALE = 0.22`。`IsoSpace.attach_actor()` 标记画面投影，幸存者用投影后的朝向选择整帧；有瞄准意图时走路整帧随瞄准方向，避免身体与握持使用不同朝向。来源与生成规格见该目录 `generation.json`，原五套切片注册由 `tools/build_survivor_atlas.py` 完成；新人由 `tools/build_recruit_atlas.py` 归一化并裁切头像，提示词见 `recruit_generation.json`；敌人各自的方向与动作模块不变。
- 幸存者握持：`SurvivorWeaponRig` 的 8×8×8 原帧像素挂点驱动现有五种武器（卡宾、长管、霰弹、斧、锤），不增加身体或武器位图。原帧手部通过 `hand_occlusion.gdshader` 在握柄上重绘，头发层沿用原帧；背向三个朝向将整个握持节点放到身体后方，握点沿原帧袖口外缘校准；北向额外向持握侧外撇 15°，让枪身从肩侧露出，所有局部层仍留在角色的 Y 排序组。后坐同时移动身体、原手部和枪。近战通过 `CombatWeaponVisualV1` 读取 `CombatRuntime` 的蓄力/恢复阶段，命中当步显示接触帧与挥砍弧；重复 `present()` 不累积旋转，也不推进规则时钟。远程沿用 `show_fire()` 事件触发的 0.24 秒动作，枪口闪光仅前 0.06 秒；入夜后同位置有半径约 24 像素、能量最高 0.42 的短时暖光（PROJECT_TEMP 表现参数）。
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

世界声部每个固定播放器持有单槽 `AudioStreamPolyphonic`，以实际 cue 的 stream ID 判断占用；空闲 transport 不发声，也可以保持 `stream_paused`。停止/静音清除 cue，暂停时空闲槽仍保持冻结，恢复不会补播；高优先级替换重启该槽 transport，避免音频线程尚未回收的槽导致假接受。`BusJourney` 在配置与阶段推进前校验门点/路线，正式世界搭建也提前报告缺失门点。

音量默认仍为主音量 0.8、世界 0.75、UI 0.7、非静音。静音/分类归零立即停止对应尾音并拒绝新声音；世界暂停冻结现有声流、拒绝新请求，UI 保持可用，恢复不补播。服务固定 6 个世界与 2 个 UI 声部，其中世界的 2 个优先留给搜刮、巴士和预警；重要提示可替换较低优先级声音，满载不排队。15 个 WAV 为纯 Python 标准库数学合成（Codex 辅助代码、没有 AI 音频模型或采样素材），每个峰值 0.55，`VOICE_GAIN = 0.20`（PROJECT_TEMP 表现参数，原 0.16）；8 声部满滑杆的离散峰值和不超过 0.88。`tests/audio_feedback.gd` 已纳入 `check`；`python tests/test_audio_assets.py` 可脱离引擎校验生成可复现性、注册、来源与混音余量。

## 测试与工具

- `tools/godot.py check`：导入、启动（`BH_READY`）与 `tests/` 下的单元/契约测试，任何 `SCRIPT ERROR`/`ERROR` 或 `"failures": N>0` 都判失败。
- `tests/smoke_loop.gd`（在 `check` 中）：无头跑完整一局：新档 → 出击 → 搜刮 → 战斗 → 巴士撤离 → 结算 → 重启读档 → 第二次出击；任何 SCRIPT ERROR 都会判失败。
- `python3 tools/check_ten_day.py --godot <引擎> --headless` 是单独运行的长流程回归：`campaign_ten_day.gd` 经正式 App 从第 2 天两人开局逐日选卡、完成主目标、搜集与撤离，结算与营地交易正常落盘；第 6 天退出引擎，新进程从正式进度继续到第 10 天归航，再以第三个游戏进程核对完整状态。测试仅覆写已有 `_pool_initial()` 注入固定种子 `blue-hour-ten-day-20261116`，不修改日期、资源、成员、设施或生产随机机制。过程日志与精确状态比较记录留在 `.local/`；不传 `--headless` 时另捕捉正式画面。档案身份仍由生产 Crypto 创建，并记在初始记录中；依赖该身份的敌种抽签须连同原存档身份复现。`--hunger` 在独立新档中连续三次空手归航，单独验证四份开局粮耗尽后的正式饥饿死亡，不计入十天路线。
- `PersonaDetails` 的特质摘要与成长、武器说明一起放在详情滚动正文中；`persona_ui` 保证 1024×640 和 1280×720 营地档案的实际内层滚动高度至少 140px，并核对装备、培养与呼号操作的可达性。
- 其他 `tools/*_flow.py` 是历史上针对单个系统的流程脚本，未纳入 `check`，部分在 main 上已经失效，后续可继续清理。
