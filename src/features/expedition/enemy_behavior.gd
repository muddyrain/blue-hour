class_name EnemyBehavior
extends RefCounted
## Per-enemy intent. Expedition owns stepping, attacks and durable damage confirmation.

var kind: String = EnemyRules.NORMAL
var spawn_stage: int = 0
var target_id: int = 0
var state: String = "chase"
var windup_remaining: float = 0.0


func snapshot() -> Dictionary:
	return {"kind":kind,"spawn_stage":spawn_stage,"target_id":target_id,"state":state,"windup_remaining":windup_remaining}


func restore(value: Dictionary) -> void:
	kind = value.kind
	spawn_stage = int(value.spawn_stage)
	target_id = int(value.target_id)
	state = value.state
	windup_remaining = float(value.windup_remaining)


func update(world: Expedition, actor: FieldActor, delta: float) -> void:
	if actor.health<=0:
		cancel(world,actor)
		return
	if state=="windup":
		if kind == NightHoundV1.KIND:
			windup_remaining = maxf(0.0, windup_remaining - delta)
			return
		var target: FieldActor = locked_target(world)
		if target==null or not legal(world,actor,target,EnemyRules.POLICY.melee_range):
			cancel(world,actor,true)
		else:
			windup_remaining = maxf(0.0,windup_remaining-delta)
		return
	var target: FieldActor = world._nearest_target(actor,world.survivors,INF)
	if target!=null and not target.visible:
		target = null
	target_id = target.member_id if target!=null else 0
	var rushing: bool = kind==EnemyRules.RUSH and target!=null and legal(world,actor,target,EnemyRules.POLICY.rush_range) and not world.navigation.path_between(actor.position,target.position).is_empty()
	state = "rush" if rushing else "chase"
	actor.speed = EnemyRules.speed(kind,rushing,world.tuning.enemy_speed)
	if target==null and kind!=EnemyRules.NORMAL:
		actor.clear_order()


func legal(world: Expedition, actor: FieldActor, target: FieldActor, distance: float) -> bool:
	return AttackRules.evaluate(world._combatant(actor),world._combatant(target),actor.position+Vector2.UP*AttackRules.HIT_HEIGHT,distance,0,world.shot_obstacles).targetable


func locked_target(world: Expedition) -> FieldActor:
	for actor: FieldActor in world.survivors:
		if actor.member_id==target_id:
			return actor
	return null


func arm(world: Expedition, actor: FieldActor, target: FieldActor) -> void:
	target_id = target.member_id
	state = "windup"
	windup_remaining = windup_duration()
	if kind == NightHoundV1.KIND:
		actor.motion_locked = true
	actor.clear_order()
	actor.aim = target.position-actor.position
	world.combat_feedback.emit({"kind":"enemy_windup","enemy_id":actor.actor_id,"enemy_type":kind,"member_id":target_id,"remaining":windup_remaining,"elapsed":world.elapsed})


func cancel(world: Expedition, actor: FieldActor, cooldown: bool = false) -> void:
	if state=="windup":
		world.combat_feedback.emit({"kind":"enemy_cancel","enemy_id":actor.actor_id,"enemy_type":kind,"member_id":target_id,"elapsed":world.elapsed})
	reset(actor,world.tuning.enemy_speed)
	if cooldown:
		actor.cooldown = attack_interval(world.tuning.enemy_interval)


func reset(actor: FieldActor, normal_speed: float) -> void:
	state = "chase"
	target_id = 0
	windup_remaining = 0.0
	actor.speed = EnemyRules.speed(kind,false,normal_speed)
	actor.aim = Vector2.ZERO
	if kind == NightHoundV1.KIND:
		actor.motion_locked = false


func windup_duration() -> float:
	return NightHoundV1.WINDUP if kind == NightHoundV1.KIND else EnemyRules.POLICY.windup


func attack_interval(original: float) -> float:
	return NightHoundV1.INTERVAL if kind == NightHoundV1.KIND else original
