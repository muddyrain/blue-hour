class_name EnemyRules
extends RefCounted
## PROJECT_TEMP types and deterministic task-identity buckets; no mutable RNG or IO.

const NORMAL: String = "normal_zombie_v1"
const RUSH: String = "rush_zombie_v1"
const HEAVY: String = "heavy_zombie_v1"
const POLICY: Dictionary = {"id":"BH_ENEMY_TYPES_V1","rush_hp":36.0,"rush_speed":58.0,
	"rush_range":95.0,"heavy_hp":96.0,"heavy_speed":23.0,"heavy_damage":6.0,
	"windup":0.5,"melee_range":28.0,"weights":[[100,0,0],[85,15,0],[65,25,10],[45,30,25]]}


static func pick(identity: String, index: int, stage: int) -> String:
	var roll: int = (String(POLICY.id)+":"+identity+":"+str(index)+":"+str(stage)).sha256_text().substr(0,8).hex_to_int()%100
	var weights: Array = POLICY.weights[stage]
	return NORMAL if roll<int(weights[0]) else RUSH if roll<int(weights[0])+int(weights[1]) else HEAVY


static func health(kind: String, normal: float) -> float:
	return POLICY.rush_hp if kind==RUSH else POLICY.heavy_hp if kind==HEAVY else normal


static func speed(kind: String, rushing: bool, normal: float) -> float:
	return POLICY.heavy_speed if kind==HEAVY else POLICY.rush_speed if rushing else normal


static func name_for(kind: String) -> String:
	return "疾奔" if kind==RUSH else "重压" if kind==HEAVY else "普通"


static func snapshot_problem(row: Dictionary, world: Dictionary, receipt: Dictionary) -> String:
	var value: Variant = row.get("behavior")
	if not value is Dictionary or value.size()!=5 or not value.has_all(["kind","spawn_stage","target_id","state","windup_remaining"]):
		return "ENEMY_BEHAVIOR_FIELDS"
	if not value.kind is String or value.kind not in [NORMAL,RUSH,HEAVY] or not SurvivalContracts.integer(value.spawn_stage,0,3) or not SurvivalContracts.integer(value.target_id,0,SurvivorRoster.MAX_MEMBER_ID) or not value.state is String or value.state not in ["chase","rush","windup"] or not SurvivalContracts.number(value.windup_remaining) or value.windup_remaining<0 or value.windup_remaining>POLICY.windup:
		return "ENEMY_BEHAVIOR_VALUES"
	var actor: Dictionary = row.state
	var expected: String = NORMAL if actor.actor_id>=10000 else pick(receipt.transaction_id,int(actor.actor_id),int(value.spawn_stage))
	if SortieSnapshot.task_version(world.get("version")):
		for resolution: Dictionary in world.task_event.resolutions:
			if resolution.reason=="spawned" and resolution.enemy_id==actor.actor_id: expected=NORMAL
	if value.kind!=expected or value.spawn_stage>world.threat.stage or actor.max_health!=health(value.kind,54.0) or actor.speed!=speed(value.kind,value.state=="rush",34.0):
		return "ENEMY_BEHAVIOR_SOURCE"
	if (value.state=="rush" and value.kind!=RUSH) or (value.state=="windup" and value.kind!=HEAVY) or (value.state!="windup" and value.windup_remaining!=0):
		return "ENEMY_BEHAVIOR_PHASE"
	var target: Dictionary = SortieSnapshot._member(world.survivors,int(value.target_id))
	if value.target_id!=0 and (target.is_empty() or target.state.health<=0 or not target.state.visible or int(target.state.activity) in [2,3]):
		return "ENEMY_BEHAVIOR_TARGET"
	if value.state in ["rush","windup"]:
		if target.is_empty() or (value.state=="windup" and (actor.activity!=FieldActor.Activity.IDLE or actor.cooldown!=0)):
			return "ENEMY_BEHAVIOR_ACTIVE"
		var distance: float = SortieSnapshot._vec(actor.position).distance_to(SortieSnapshot._vec(target.state.position))
		if distance>=(POLICY.melee_range if value.state=="windup" else POLICY.rush_range):
			return "ENEMY_BEHAVIOR_DISTANCE"
		var shooter: AttackRules.Combatant = AttackRules.Combatant.new(SortieSnapshot._vec(actor.position),true,actor.visible,true)
		var victim: AttackRules.Combatant = AttackRules.Combatant.new(SortieSnapshot._vec(target.state.position),true,true,false)
		var decision: AttackRules.Decision = AttackRules.evaluate(shooter,victim,shooter.foot+Vector2.UP*AttackRules.HIT_HEIGHT,POLICY.melee_range if value.state=="windup" else POLICY.rush_range,0,SortieSnapshot.supply_for_world(world).layout.shot_obstacles())
		if not decision.targetable:
			return "ENEMY_BEHAVIOR_LOS"
	return ""
