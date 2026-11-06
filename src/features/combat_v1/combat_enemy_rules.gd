class_name CombatEnemyRules
extends RefCounted
const TOXIC: String="toxic_zombie_v1"
static func pick(identity: String,index: int,stage: int) -> String:
	return ToxicV1.pick(identity,index,stage)

static func snapshot_problem(row: Dictionary,world: Dictionary,receipt: Dictionary,summoned: bool=false) -> String:
	if not SortieSnapshot.combat_version(world.get("version")): return EnemyRules.snapshot_problem(row,world,receipt,summoned)
	var state: Dictionary=row.state
	var behavior: Variant=row.get("behavior")
	if not behavior is Dictionary or behavior.size()!=5 or not behavior.has_all(["kind","spawn_stage","target_id","state","windup_remaining"]): return "COMBAT_ENEMY_FIELDS"
	if not SurvivalContracts.integer(behavior.spawn_stage,0,int(world.threat.stage)) or behavior.state not in ["chase","rush","windup"] or not SurvivalContracts.integer(behavior.target_id,0,5) or not SurvivalContracts.number(behavior.windup_remaining): return "COMBAT_ENEMY_STATE"
	for resolution: Dictionary in world.task_event.resolutions:
		if resolution.reason=="spawned" and resolution.enemy_id==state.actor_id: summoned=true
	if summoned or state.actor_id>=10000: return EnemyRules.snapshot_problem(row,world,receipt,true)
	var source: Variant=world.combat.spawns.get(str(int(state.actor_id)))
	if not source is Dictionary or source.size()!=3 or not source.has_all(["kind","stage","fallback"]) or source.stage!=behavior.spawn_stage: return "COMBAT_ENEMY_SOURCE"
	var rolled: String=pick(receipt.transaction_id,int(state.actor_id),int(behavior.spawn_stage))
	if source.kind!=behavior.kind or (source.kind!=rolled and not (rolled==TOXIC and source.kind==EnemyRules.NORMAL and SurvivalContracts.integer(source.fallback,0,int(state.actor_id)-1) and world.combat.spawns.get(str(int(source.fallback)),{}).get("kind")==TOXIC)): return "COMBAT_ENEMY_ROLL"
	var active_target: Dictionary=SortieSnapshot._member(world.survivors,int(behavior.target_id))
	if behavior.target_id!=0 and (active_target.is_empty() or active_target.state.health<=0 or not active_target.state.visible or int(active_target.state.activity) in [2,3]): return "COMBAT_ENEMY_TARGET"
	if behavior.state=="windup" and (state.activity!=FieldActor.Activity.IDLE or state.cooldown!=0): return "COMBAT_ENEMY_WINDUP"
	if behavior.kind==TOXIC:
		if state.max_health!=64.0 or state.speed!=26.0 or behavior.state!="chase" or behavior.windup_remaining!=0: return "TOXIC_ACTOR_SOURCE"
		return ""
	# Reuse strict old shape/phase/spatial checks on a projection with the new source already proven.
	var projected: Dictionary=row.duplicate(true)
	var old_kind: String=EnemyRules.pick(receipt.transaction_id,int(state.actor_id),int(behavior.spawn_stage))
	projected.behavior.kind=old_kind
	if behavior.kind!=old_kind:
		# Validate all non-source constraints directly when the old roll differs.
		if state.max_health!=EnemyRules.health(behavior.kind,54.0) or state.speed!=EnemyRules.speed(behavior.kind,behavior.state=="rush",34.0): return "COMBAT_ENEMY_STATS"
		if (behavior.state=="rush" and behavior.kind!=EnemyRules.RUSH) or (behavior.state=="windup" and behavior.kind!=EnemyRules.HEAVY) or behavior.windup_remaining<0 or behavior.windup_remaining>0.5 or (behavior.state!="windup" and behavior.windup_remaining!=0): return "COMBAT_ENEMY_PHASE"
		var target: Dictionary=SortieSnapshot._member(world.survivors,int(behavior.target_id))
		if behavior.target_id!=0 and (target.is_empty() or target.state.health<=0 or not target.state.visible or int(target.state.activity) in [2,3]): return "COMBAT_ENEMY_TARGET"
		if behavior.state in ["rush","windup"]:
			if target.is_empty(): return "COMBAT_ENEMY_ACTIVE"
			var limit: float=28.0 if behavior.state=="windup" else 95.0
			if not AttackRules.evaluate(AttackRules.Combatant.new(SortieSnapshot._vec(state.position),true,state.visible,true),AttackRules.Combatant.new(SortieSnapshot._vec(target.state.position),true,true,false),SortieSnapshot._vec(state.position)+Vector2.UP*28.0,limit,0.0,SortieSnapshot.supply_for_world(world).layout.shot_obstacles()).targetable: return "COMBAT_ENEMY_LOS"
		return ""
	return EnemyRules.snapshot_problem(row,world,receipt)
