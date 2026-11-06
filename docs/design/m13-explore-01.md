# M13-EXPLORE-01：街区探索、车辆与果树

基线main `890bff3097a34bafbc6c37df8dedf370e921ae1f`，#17精确已审 `153094f130918c37a6d8b9e6faa18e0ffc6b5f25` 已普通合入。当前唯一目录/分支 `codex/m13-explore-01`。新产物预算768MiB，原profile/失败/历史不动。下列接口在委派前冻结；新增数值为PROJECT_TEMP，正式门禁BLOCKED。

## 版本和权威

新旅程build5在原build4增加 `exploration:{version:1,policy_id:"BH_EXPLORATION_V1"}`。仅非终局普通行动启用generated9/rules10/world15及布局4；旧build4/world14保持原布局/预算/认证/指纹。新旅程终局仍原generated8/rules9/world14，不扩终局预算/四次准备规则。新描述拥有同一布局、对象、站点、主预算/可选预算及目标；原WorldSites/Expedition/事务/结算仍唯一拥有进度、携带和确认，目标计数只读派生。

新布局复用NeighborhoodLayout._assemble最后的显式expanded=true几何分支，旧默认false原V3 canonical保持；新布局4使用独立域/尺寸网格、保证远段食品/装备建筑，并冻结props与分散合法敌人候选。新Action严格再生成/绑定新布局与全部站点，不删除新几何后冒称旧V3认证。旧任务原奖励/武器/道具/能力/救援选择从原策略生成，仅提取/重新认证其真实来源，再构造新完整描述。新power来源先完整新认证，之后仅已认证来源可投影原库存校验；旧来源不会被新分流放宽。

## API与文件所有权

- A独占所有既有文件、共享Main/Actions/StreetLayout/导航/工作/战斗/快照/结算、Git、引擎、UID、统一验收与媒体。A新建ExplorationState/ExplorationActions及实际流程驱动。
- B仅新 `src/features/exploration/exploration_layout.gd`、`exploration_sites.gd`、`tests/exploration_generation.gd`；纯数据、FieldNavigation允许，无Node/磁盘/引擎/Git/UID。完整36张纯生成/后碰撞导航验收由A统一跑。
- C仅新 `src/features/exploration/exploration_prop.gd`、`exploration_objectives.gd`、`assets/exploration/*.svg`；只读表现与目标列表，无随机/状态owner，不动共享文件/引擎/Git/UID。

`ExplorationLayout`：`policy()->Dictionary`；`generate(seed:String,size:String,topology:String)->Dictionary`；`validate(value:Variant,cached:bool=true)->String`；`resource(data:Dictionary)->StreetLayout`；`is_map_id(value:Variant)->bool`。布局严格17键=原16键+objects，version4/id前缀explore_v1_；同输入有限3次+同规模同拓扑回退。object严格 `{id,kind,variant,point,collision,work_point}`：kind vehicle/fruit_tree；id vehicle_01/tree_01；variant sedan/van/apple_tree；point为脚点，collision世界Rect数组，work_point可站侧边。小/中/大2560×1920/3584×2688/4608×3456，网格4×3/5×4/6×5。资源blockers由A把objects.collision加入，射线仍只建筑/院墙，车/树不新增LOS。after-prop导航计算Dmax、全部建筑门/objects work_point/巴士/救援与spawnpoints可达，保护完整sweep+集合/路口。允许validate缓存完整原文指纹，无每帧重验。

`ExplorationSites`：`generate(layout:Dictionary,type:String,cash:int,food:int,weapons:int,action_id:String)->Dictionary` 返回 `{sites,objective,optional_objectives,metrics}`；`problem(layout,value,type,cash,food,weapons,action_id)->String` 严格重算；`objective_rows(generated:Dictionary,facts:Dictionary,rescue_done:bool=false)->Array[Dictionary]` 只读；`site_point(layout,site)->Vector2`。sites保留cash/food主id与原预算；每站原7键+source/object_id/work_mode，可含point与主武器drop。source为primary/optional_building/vehicle/fruit_tree；object_id为bNN或vehicle_01/tree_01；work_mode indoor/outdoor；原主建筑30/空投12、可选建筑18、车8、树6。optional建筑id optional_bNN。主武器仍只cash；可选不发武器/道具/能力。最大15，按实际定义精确认证。objective原 `{task_id,site_ids,member_id}` 由A补member_id；optional_objectives两条 `{id,title,site_ids}` 独立hash挑2类。metrics `{dmax,routes}`，routes每site_id对应 `{length,zone,base_walk_seconds}`，按真实后碰撞path、0.35/0.65阈值。主目标至少一处中/远、每图近中远、中大远点≥2，不得用装饰点充数。objective_rows字段 `{id,title,optional,done,total,complete,site_ids,hint}`；真实事实派生，非奖励写者。

`ExplorationProp extends FieldProp`：`configure(definition:Dictionary)`，定义即layout.objects一项；继承title/searched/primary_target/reward_hint/ui_theme，复用原update_work签名显示负责人/进度，仍纯表现。小汽车/厢车/果树原创SVG，与原房屋俯视/阴影/尺度相容，实际宽约140—160（巴士240），树干小碰撞。`present(state:Dictionary,worker_id:int=0,worker_name:String="",occluded:bool=false)` 可采/进行/采空，树冠可淡化，A从实际脚点判断遮挡。

`ExplorationObjectives extends VBoxContainer`：signal `locate_requested(objective_id:String)`；`present(rows:Array[Dictionary])`。只3个紧凑单行（主/可选、完成数、定位按钮），每行≤24高，根≤76高、宽约264，完整说明tooltip；无额外大标题（共享MissionPanel原收起按钮由A控制显隐）。点击只emit，A按定义循环尚未完成site_id移动镜头+短标记，不改变队员命令/工作。

## 验收与交付

当前Mac Godot4.7.2/Compatibility，后台不抢焦点。先小范围生成/实际预检，36生成确定性/类型/预算/真实path分区/加入碰撞后可达/巴士净空；中图真实两人车+另一站点/采树/独立取消/中远移动/提前撤离和唯一入库；一次安全暂存后新PID覆盖已完成车树、两jobs、个人因子、原支援重建。旧14代表跨PID，有限小/大加载与耗时；户外受伤/死亡自身清理、全灭不入库、重复/非法对象与最快工时受控补齐。最终冻结公开check/来源，失败按影响重验。

一次45—60秒最终1×流式短片，3—4图，真实图/生成路线图明确区分；不保存全片PNG/重复多份媒体。一个轻量私有ZIP含HEAD/base/精确diff/必要恢复日志，正常隔离源码入口；不导出/不clone/不合并本轮/不Release。物理输入/人工手感/显示器FPS/其它平台未验须注明。下一步仅记录“目标驱动的较完整旅程”。
