# 武器V1接线

`CombatPatternsV1`只计划几何，不持有弹匣、生命、经验、磁盘或随机状态。所有数值是PROJECT_TEMP；机制为PROJECT_ADAPTATION，不宣称原作精确公式。

- 斧输入实际脚点和锁定方向，在命中时重新调用`axe_plan`。只返回距离/稳定ID排序的最多3行`{id,hits:1}`。
- 霰弹输入实际脚点、原握持枪口和锁定方向。`shotgun_plan`返回五条截到首个碰撞的射线及按ID聚合的`targets`。未命中射线的`id=-1`，敌人ID 0合法。A对每行一次应用`单颗有效伤害×hits`，一次扳机只扣一发。障碍物与旧AttackRules同样投影到28px命中平面；所有可伤目标先过严格脚点范围。
- `assets/combat_v1/weapons/fire_axe_v1.tres`及`shotgun_v1.tres`是独立定义，引用同目录`axe_view.tres`/`shotgun_view.tres`，不修改旧Definitions或MAGAZINES表。
- 将`CombatWeaponVisualV1`添加为ActorVisual子节点并`bind_actor_visual(actor_visual)`。原`_update_hold`完成之后调用`present(weapon_id,heading,phase,progress)`，每次使用原姿态为基底，因此不会累积偏转。它调整同一武器/手臂/上身握持，只读阶段为`idle/windup/strike/recover/reload`，进度0—1；不启用process，也不推进自己的时钟。斧实际命中时`recover,0`立即显示完整短弧，前20%恢复内淡出；恢复45%后武器/上身归位。霰弹`strike/fire`可显示额外后坐；`reload`按已存换弹进度做泵握动作。五弹迹由A在原效果层按`rays`画短线；视觉绝不再判伤。
- 原ActorVisual仍使用各方向的作者握点和原Y排序；该组件不改人物脚点、腿步态、接触偏移或存档字段。

玩家简短帮助：消防斧近身扇形挥击，最多3个目标，无换弹；霰弹枪每次5颗、4发弹匣，近距离适合清群。reach词缀的斧文案应为“延长握柄：距离×1.15”，枪仍为“延伸瞄具：射程×1.15”。

`tests/combat_patterns_v1.gd`只检查纯几何与只读姿态；扣弹/单敌唯一XP/持久恢复由A统一原场景验收。B没有运行引擎。
