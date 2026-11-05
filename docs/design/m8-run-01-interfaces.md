# M8-RUN-01 · 并行接口起点

基线 `decab5459789e2e6c29bb3153959dc5fbb24bd51`，依赖未合并 #11。
新建旅程才启用 PROJECT_TEMP 短局 V1；旧记录不从 day 推算阶段。

## 所有权

A 独占 Main、Expedition、FieldActor、SortieSnapshot、FrozenSettlement、ProductionProgress、EnemyState、DailyActions、事务/死亡/成长/奖励写者及新集成适配文件。
B 只写 `src/features/campaign/campaign_rules.gd`、可选 `campaign_display.gd` 和 `tests/campaign_rules.gd`。
C 只写 `src/features/encounter/boss_definition.gd`、`boss_behavior.gd`、`boss_warning.gd` 和 `tests/boss_behavior.gd`。
B/C 不修改共享入口、全局格式版本、Godot 项目配置、公共检查驱动或其他模块。

## 阶段接口（B）

`CampaignRules` 为无 IO 的纯函数类。A 在既有 journey 中保存 campaign：
`{version:1,mode:"short_v1",run_id:<profile_id>,preparations:0..4,outcome:"ACTIVE"|"VICTORY"|"DEFEAT",result_transaction:""|<transaction_id>}`。

- `initial(run_id: String) -> Dictionary`
- `problem(value: Variant, run_id: String = "") -> String`：严格字段/范围/身份，空字符串表示通过。
- `context(value: Dictionary) -> Dictionary`：`{version:1,stage:"preparation"|"breakout"|"finale",is_finale:bool,pressure:float}`。0/1 次已确认准备为筹备，2/3 为突围，4 为终局；压力依次 1.0/0.90/1.0。
- `can_depart(value: Dictionary) -> bool`
- `display(value: Dictionary) -> Dictionary`：只读 `{title:String,detail:String,progress:String}`，用于菜单/任务卡。

实际次数及结果只由 A 在原冻结结算/确认保存链推进，不由 B 改营地天数或发奖励。

## 首领接口（C）

`BossDefinition` 集中附件 V1 参数，提供 `POLICY: Dictionary`，首领不修改 `EnemyRules.POLICY`。
`BossBehavior` 为纯状态机，不持有 Expedition/FieldActor，不扣血、不刷怪、不提交 XP。

- `configure(identity: String) -> void`
- `step(delta: float, health_ratio: float, alive: bool, targets: Array[Dictionary], position: Vector2) -> Array[Dictionary]`
- `acknowledge(request_id: String, result: Dictionary) -> void`
- `snapshot() -> Dictionary` / `restore(value: Dictionary) -> void`
- `static problem(value: Variant, identity: String) -> String`

目标输入 `{member_id:int,position:Vector2,melee_legal:bool,slam_legal:bool}` 由 A 从既有目标/LOS/保护规则派生。输出请求包含稳定 `id`、`kind:"melee"|"slam"|"summon"`、`target_id`、冻结 `position:[x,y]`；summon 另含 `threshold`、`count`。请求由 A 同步消费并 acknowledge 实际处理事实；待处理请求也进入快照，恢复不得重置或丢失。两种攻击互斥，起手/冷却/阈值与处理事实全部可恢复。首领死亡立即停止攻击。A 在到期重新核对合法范围/LOS/保护并调用原伤害与刷怪 owner。

`BossWarning` 只读行为 snapshot 和首领生命，可由 A 提供状态绘制地面危险区及名称/生命；具体只读更新函数由 C 的接入说明固定。

## A 的行动与结果边界

新行动描述冻结 campaign context、原 generated/layout 身份和终局首领身份/出生点。新世界版本保存同一首领实例、权威生命、状态机、已处理召援及实际敌人；旧世界指纹分支保留。
终局凭证绑定当前事务、唯一首领真实伤害/死亡事件和同次原巴士撤离。全灭优先；归航预览不是持久胜利。确认失败保留冻结候选，重试不能重复推进或奖励。结束旅程可查看队伍与结果，明确新旅程才产生新身份。
