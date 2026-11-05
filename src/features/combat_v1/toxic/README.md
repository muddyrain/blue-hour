# 毒气 V1 接线

此目录只计算请求/只读表现，不写 HP、死亡、经验或磁盘。所有参数为 PROJECT_TEMP。

- `ToxicV1.plan(state, delta, casters, members, obstacles)` 在玩家攻击和实际敌人死亡之后调用；暂停、过场、冻结、结束不调用。输入脚点为世界地面坐标，member.id 使用成员 ID，caster.id 使用原敌人 actor ID（0 合法）。成员 available 由原室内/户外可受伤政策给出。
- `casters[str(enemy_id)].phase == "windup"` 时停走，朝向冻结的 `point`；`progress=1-remaining/.9`。其余阶段沿原导航/普通接触攻击。A 独占在场毒气者上限和自然出生来源认证。
- `plan` 不改输入。第一次符合起手条件只锁点并获得完整 .9s 起手；之后模拟 delta 消耗起手，完成时核实际来源脚点、锁点和墙体。投放后六秒冷却，区域在落地后 .75/1.5/2.25/3s 四次命中，60px 圈边界包含，投放距离沿原规则严格小于220px。
- `releases` 为成功投放事实：`id/source_id/sequence/point/source_point`。区域增加 `age/next_tick`，来源死亡后仍保留。A 应在新 world 版本内绑定原出生事实、地图边界和两点 LOS，不可把旧模式或特殊援军套入新来源。
- `pending={hits,cursor}` 冻结整批真实目标，hit 为 `zone_id/tick/member_id/amount/member_point`。按原序将原 hit 交既有伤害 owner；成功后 `ack(state, original_hit)`。原 owner 的 HP 因果、永久死亡与 ack 必须属于可恢复边界。失败保持暂停，重试原 pending 后再恢复世界运动；pending 存在时 plan 不消费 delta、不重选目标。已提交 hit 重放不能越过下一个成员。
- `problem` 只验证严格版本/字段、计数/时钟、release-zone 一致、pending 去重/顺序/圈内几何，不能替代 A 对实际世界、出生源、墙体、持久收据的认证。pending 的 `member_point` 允许 A 复核历史命中 LOS，不随重试时位置改变。
- `ToxicVisualV1` 挂原地面效果层，`present(state)` 只读，`advance(delta, active)` 只推进消退动画。警告为虚线/十字和进度弧；生效为低透明气场/实线圈，范围不变，危险消退 .28s。没有 process 回调。
- `ToxicCarrierVisualV1` 挂 `ActorVisual`（脚点局部坐标），`present(heading, casting, progress)` 画原创肩背双毒囊和定向蓄力手臂；倒地时由 A 隐藏。无需改变原普通感染者图集/步态。`carrier_sacs.svg` 为本轮手工编写原创 SVG，无外部素材。

`tests/toxic_v1.gd` 是纯状态/几何夹具，由 A 统一运行；不声称实际 HP、永久死亡、跨进程或自然流程已通过。
