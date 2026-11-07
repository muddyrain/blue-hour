class_name PumpEncounter
extends Node2D
## The existing encounter owns identity, defeat and summons. This node only runs its charge.

var state: Dictionary = initial()
var walls: Array[Rect2] = []


static func initial() -> Dictionary:
	return {"lane":{}, "windup":0.0, "recovery":0.0, "cooldown":0.0, "sequence":0, "hits":[]}


static func collision_walls(layout: StreetLayout) -> Array[Rect2]:
	var result: Array[Rect2] = layout.blockers()
	return result


static func problem(value: Variant, generated: Dictionary, stopped: bool, alive: bool) -> String:
	if not value is Dictionary or value.size() != 6 or not value.has_all(initial().keys()):
		return "PUMP_ENCOUNTER_FIELDS"
	if not stopped or not alive:
		return "" if TransactionReceipt.same(value, initial()) else "PUMP_INACTIVE_CHARGE"
	for key: String in ["windup", "cooldown", "recovery"]:
		if not SurvivalContracts.number(value[key]) or value[key] < 0.0:
			return "PUMP_CHARGE_CLOCK"
	if value.windup > PumpCharge.WINDUP or value.recovery > PumpCharge.RECOVERY or value.cooldown > PumpCharge.COOLDOWN \
			or not SurvivalContracts.integer(value.sequence, 0, RunSave.MAX_COUNTER) or not value.hits is Array:
		return "PUMP_CHARGE_FIELDS"
	var station: StreetLayout = PumpStationLayout.resource(generated.layout)
	if station == null:
		return "PUMP_CHARGE_LAYOUT"
	var issue: String = PumpCharge.problem(value.lane, collision_walls(station))
	if not issue.is_empty():
		return issue
	if value.lane.is_empty():
		return "" if value.windup == 0.0 and value.hits.is_empty() and value.recovery <= value.cooldown else "PUMP_CHARGE_IDLE"
	for key: String in ["from", "target", "to"]:
		if not station.world_bounds.has_point(WorldLayout.point(value.lane[key])):
			return "PUMP_CHARGE_BOUNDS"
	if value.sequence == 0 or value.recovery > 0.0 or value.cooldown > 0.0 or (value.windup > 0.0 and not value.hits.is_empty()):
		return "PUMP_CHARGE_ACTIVE"
	var seen: Array[int] = []
	for member: Variant in value.hits:
		if not SurvivalContracts.integer(member, 1, 5) or int(member) in seen:
			return "PUMP_CHARGE_HITS"
		seen.append(int(member))
	return ""


func holds() -> bool:
	return not state.lane.is_empty() or state.recovery > 0.0


func reset() -> void:
	state = initial()
	queue_redraw()


func advance(delta: float, encounter: EncounterRuntime) -> void:
	var world: Expedition = encounter.world
	var boss: FieldActor = encounter.actor
	state.cooldown = maxf(0.0, state.cooldown - delta)
	state.recovery = maxf(0.0, state.recovery - delta)
	if state.lane.is_empty():
		if state.cooldown == 0.0:
			_arm(encounter)
	else:
		state.windup = maxf(0.0, state.windup - delta)
		if state.windup == 0.0:
			_resolve(world, boss)
	queue_redraw()


func _arm(encounter: EncounterRuntime) -> void:
	var boss: FieldActor = encounter.actor
	var target: FieldActor
	for member: FieldActor in encounter.world.survivors:
		if not encounter.legal(member, PumpCharge.RANGE):
			continue
		if target == null or boss.position.distance_squared_to(member.position) < boss.position.distance_squared_to(target.position):
			target = member
	if target == null:
		return
	var lane: Dictionary = PumpCharge.arm(boss.position, target.position, walls)
	if lane.is_empty():
		return
	state.lane = lane
	state.windup = PumpCharge.WINDUP
	state.sequence += 1
	boss.aim = (target.position - boss.position).normalized()
	boss.clear_order()
	encounter.world._show_notice("破阵者蓄力 · 横移离开虚线冲锋道，或退到混凝土墙后")
	encounter.world.combat_feedback.emit({"kind":"pump_charge_warning", "lane":lane.duplicate(true),
		"elapsed":encounter.world.elapsed, "sequence":state.sequence})


func _resolve(world: Expedition, boss: FieldActor) -> void:
	var lane: Dictionary = state.lane
	var heading: Vector2 = (WorldLayout.point(lane.target) - WorldLayout.point(lane.from)).normalized()
	for member: FieldActor in world.survivors:
		if member.health <= 0.0 or not member.visible or int(member.member_id) in state.hits or not PumpCharge.hit(lane, member.position):
			continue
		var before: float = member.health
		if not member.take_damage(PumpCharge.DAMAGE, heading):
			world.toggle_pause()
			world._show_notice("冲锋伤害待保存 · 已暂停，可继续重试同一次冲锋")
			return
		state.hits.append(member.member_id)
		world._clear_dead_worker()
		world._hit_effect(member.position, before - member.health, true)
		world.combat_feedback.emit({"kind":"pump_charge_hit", "member_id":member.member_id,
			"applied_damage":before - member.health, "elapsed":world.elapsed, "sequence":state.sequence})
	var stop: Vector2 = WorldLayout.point(lane.to)
	if world.navigation.is_clear(stop):
		boss.position = stop
	boss.visual.show_attack(heading)
	world.combat_feedback.emit({"kind":"pump_charge_resolved", "lane":lane.duplicate(true), "sequence":state.sequence,
		"hits":state.hits.duplicate(), "elapsed":world.elapsed})
	state.lane = {}
	state.hits = []
	state.cooldown = PumpCharge.COOLDOWN
	state.recovery = PumpCharge.RECOVERY


func _draw() -> void:
	PumpCharge.draw_warning(self, state.lane)
