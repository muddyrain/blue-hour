# M11-POWER-01：特殊能力与紧凑出击界面

基线 main `664f8a553c5a1d265d365d19f0035861de71e486`，包含已审 #15 `03e48952d7bf3ce7ab25d8c2ecf283f87844cadd`。以下为实现前冻结的最小合同；正式生产门禁仍 BLOCKED。

## 模式、时钟与来源

只在新建旅程启用 build version3 / powers version1；旧营地和世界11/12保留原模式和原指纹，不改玩家原件。generated8 增加显式 `powers` 能力扩展，旧投影去除此字段后仍必须完整通过原认证；rules9 保留。新世界13单独绑定能力策略和全量 jobs。特殊槽每日总共一次，换装不新增机会；每次行动的装备与已有清单在原行动描述冻结。

`SpecialPowers` 是无 Node、Actor、磁盘依赖的纯策略：`POLICY` 两个 ID 对应 name/duration/move_factor；`initial(binding, equipped)` 产生 `{version:1,binding,equipped,accepted:[]}`；`request(state)` 产生 `{id,ability_id}`；`accept(state,request,at)` 返回新状态；`problem(state,binding,equipped,elapsed)` 严格验证字段、身份、唯一次数、合法有效区间；`remaining(state,elapsed)`、`move_factor(state,elapsed)`、`frozen(state,elapsed)` 只读派生。accepted 最多一项 `{id,ability_id,at,until}`，ID 绑定 transaction_id 与能力 ID，until 必须等于 at+duration。效果不另存可漂移倒计时。

原模拟 elapsed 是效果唯一时钟：暂停、过场、结束和 IO 阻塞不前进。玩家移动只通过 `effective_speed()` 读取原 speed 与能力因子，不改写基础 speed。冻结只停敌人移动、攻击、行为和毒气施放者时钟；首领受非致命伤仍由原BossBehavior记录最低生命/一次性血量阈值事实，动作剩余与锁定不变，请求到解冻后才由原owner执行；区域时钟、玩家、工作、威胁、刷怪、巴士照常。跨到期边界按生效部分/非生效部分推进，避免欠账补放。

原主装备站点完成携带稳定样本；独立 hash 域从 seed/action/site 与未拥有清单选择，不消费原随机源。只由原 FrozenSettlement 在撤离确认后入库；来源保存原 context、departure owned 与 transaction。营地编辑走原 CampEdit，激活走独立 typed power 请求与原 RunTransaction/Journal 的原子世界提案、ACK/claim，失败重试保留原请求。support 与 powers 分开，既有支援替换世界时必须保留能力和全部 jobs。

## 界面草图与文件所有权

1280×720：左上约300×112可收起目标；上中约210×84威胁/天数/时间；右上资源与暂停；左侧约184宽 Q/E/3 图标技能列；右侧约208宽2—4人纵列；下方紧凑巴士入口与短通知。沿用 Theme，浮层可键盘/点击开启且不偷地图命令，不隐式暂停。队员完整地点由 tooltip/展开说明保留，结算仍用原位置。

- A：原任务/营地/配装、Expedition/Actor/Contacts、Snapshot、事务/Journal、毒气/首领接线、共享适配器、Git和统一引擎验收。
- B：仅新 `src/features/powers/special_powers.gd` 和 `tests/special_powers.gd`，按上面的纯策略 API 实现与局部用例；不启动引擎、不写 UID、不改存档或 Git。
- C：仅 `src/features/expedition_hud/expedition_hud.gd`、`src/features/basic_support/basic_support_panel.gd`；新 `src/features/powers/power_slot_panel.gd`、`power_effect_view.gd` 和 `assets/powers/*.svg`。只读 UI/场景表现，原信号和字段兼容；不启动引擎、不写 UID、不改存档或 Git。

PowerSlotPanel: signal `activation_requested`，`present(title,status,remaining,duration,enabled,ability_id)`；PowerEffectView: `present(actors:Array[Dictionary], enemies:Array[Dictionary], speed_active:bool, freeze_active:bool, clock:float)`，行仅含 position/moving/alive，不保留 Actor 引用。图标与场景效果不拥有玩法状态。

## 依据与验收

经典 app740080 官方 [2019-05-16 Update0.50](https://store.steampowered.com/news/posts/?appids=740080&enddate=1568884297&feed=steam_community_announcements)支持每日充能装备型 Special Powers、基础能力冷却方向；[2018-10-26 更新](https://store.steampowered.com/news/posts/?appids=740080&enddate=1541763999)提到 Speed Boost / Map Freeze。中文名、一槽、投放、×1.5/8秒、全场冻结4秒和首领处理均 PROJECT_ADAPTATION / PROJECT_TEMP；本机1.7精确参数 UNKNOWN。不复制参考图素材，不运行原作。

当前 Mac 固定 Godot4.7.2/Compatibility、隔离 profile。验真实获取/确认/配装/使用、每日次数/输入、实际位移、敌人与毒区分钟、有效期跨PID、原IO/ACK重试、世界12/旧营地兼容和最终公开 check。新候选源码/原生入口、物理输入与未验平台分开报告。新增 `.local/m11-power-01` 预算 ≤768MiB；不删除历史目录。
