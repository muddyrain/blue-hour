class_name SpecialInfectedFeedback
extends Node2D
## Read-only bridge from existing authoritative phases to enemy art and danger cues.
## It owns no attack timer, gameplay flag, save field or damage callback.

var world: Expedition
var _boss_sequence: int = -1
var _boss_released_at: float = -1.0
var _boss_point: Vector2 = Vector2.ZERO
var _boss_radius: float = 0.0
var _boss_heading: Vector2 = Vector2.RIGHT


func _init() -> void:
	material = InfectedDangerGeometry.unshaded()


func refresh(value: Expedition) -> void:
	world = value
	for actor: FieldActor in world.enemies:
		if actor.visual == null or actor.enemy_behavior == null or actor.health <= 0.0:
			continue
		if world.encounter != null and world.encounter.is_boss(actor):
			_present_boss(actor)
		elif actor.enemy_behavior.kind == BurstRuntimeV1.KIND and world.combat.burst != null:
			var state: Dictionary = world.combat.burst.state
			var progress: float = 1.0 - float(state.remaining) / BurstRuntimeV1.WINDUP
			var phase: StringName = &"windup" if state.phase in ["windup", "confirming"] else &"chase"
			actor.visual.present_special(phase, progress, actor.aim)
		elif actor.enemy_behavior.kind == NightHoundV1.KIND:
			var behavior: EnemyBehavior = actor.enemy_behavior
			actor.visual.present_special(&"windup" if behavior.state == "windup" else &"chase",
				1.0 - behavior.windup_remaining / NightHoundV1.WINDUP, actor.aim)
		elif actor.enemy_behavior.kind == ToxicV1.KIND:
			_present_toxic_release(actor)
	# Pump cues are also presentation-only; keep their footprint visible under night tint.
	if world.encounter != null and world.encounter.pump != null:
		world.encounter.pump.material = material
	queue_redraw()


func _present_toxic_release(actor: FieldActor) -> void:
	var age: float = INF
	var heading: Vector2 = actor.aim
	for zone: Dictionary in world.combat.toxic.get("zones", []):
		if zone.source_id == actor.actor_id and float(zone.age) < age:
			age = float(zone.age)
			heading = ToxicV1._vec(zone.point) - ToxicV1._vec(zone.source_point)
	var intent: Dictionary = world.combat.toxic.get("casters", {}).get(str(actor.actor_id), {})
	actor.visual.present_special(&"release" if age < 0.30 and intent.get("phase") != "windup" else &"chase",
		age / 0.30 if is_finite(age) else 1.0, heading)


func _present_boss(actor: FieldActor) -> void:
	var encounter: EncounterRuntime = world.encounter
	# Only the visual identity changes. The heavy rule kind and saved shape stay intact.
	actor.visual.enemy_kind = BossDefinition.KIND
	if actor._enemy_tag != null:
		actor._enemy_tag.visible = false
	var phase: StringName = &"chase"
	var progress: float = 0.0
	var heading: Vector2 = actor.aim
	if encounter.pump != null:
		var pump: Dictionary = encounter.pump.state
		if not pump.lane.is_empty():
			phase = &"windup"
			progress = 1.0 - float(pump.windup) / PumpCharge.WINDUP
		elif pump.recovery > 0.0:
			phase = &"release"
			progress = 1.0 - float(pump.recovery) / PumpCharge.RECOVERY
		if is_instance_valid(encounter.pump_visual):
			# The new authored sleeve replaces the temporary geometric loading brace.
			encounter.pump_visual.visible = false
	else:
		var state: Dictionary = encounter.behavior.snapshot()
		var winding: bool = state.state in ["melee_windup", "slam_windup"]
		if winding:
			phase = &"windup"
			var duration: float = float(BossDefinition.POLICY.slam_windup if state.state == "slam_windup" else BossDefinition.POLICY.melee_windup)
			progress = 1.0 - float(state.remaining) / duration
			heading = SortieSnapshot._vec(state.point) - actor.position
			_boss_heading = heading
			_boss_point = SortieSnapshot._vec(state.point) if state.state == "slam_windup" else actor.position
			_boss_radius = float(BossDefinition.POLICY.slam_radius if state.state == "slam_windup" else BossDefinition.POLICY.melee_range)
		elif _boss_sequence >= 0 and int(state.last_handled) > _boss_sequence:
			_boss_released_at = world.elapsed
		_boss_sequence = int(state.last_handled)
		if not winding and _boss_released_at >= 0.0 and world.elapsed - _boss_released_at < 0.30:
			phase = &"release"
			progress = (world.elapsed - _boss_released_at) / 0.30
			heading = _boss_heading
	actor.visual.present_special(phase, progress, heading)


func _draw() -> void:
	if world == null or world.phase == Expedition.Phase.FINISHED:
		return
	_draw_burst()
	_draw_boss_impact()
	for actor: FieldActor in world.enemies:
		if actor.enemy_behavior == null or actor.health <= 0.0 or not actor.visible:
			continue
		if actor.enemy_behavior.kind == ScreamerPolicyV1.KIND:
			draw_set_transform(IsoSpace.to_view(actor.position))
			ScreamerVisualV1.draw_cue(self, actor.visual._screamer_phase, actor.visual._screamer_progress)
			draw_set_transform(Vector2.ZERO)
		elif actor.enemy_behavior.kind == NightHoundV1.KIND:
			_draw_hound(actor)


func _draw_burst() -> void:
	if world.combat.burst == null:
		return
	var state: Dictionary = world.combat.burst.state
	if state.phase not in ["windup", "confirming", "released"]:
		return
	var released: bool = state.phase == "released"
	var age: float = world.elapsed - float(state.event.get("at", world.elapsed))
	if released and age >= 0.30:
		return
	var point: Vector2 = SortieSnapshot._vec(state.origin)
	var progress: float = clampf(1.0 - float(state.remaining) / BurstRuntimeV1.WINDUP, 0.0, 1.0)
	var opacity: float = 1.0 - age / 0.30 if released else 0.72 + 0.28 * sin(progress * TAU * 4.0)
	InfectedDangerGeometry.rim(self, point, BurstRuntimeV1.RADIUS,
		Color(InfectedDangerGeometry.AMBER, opacity), 0.14 if released else 0.08, -1.0 if released else progress)
	if released:
		# The moving inner pressure ring never suggests a radius larger than the real hit.
		InfectedDangerGeometry.rim(self, point, BurstRuntimeV1.RADIUS * clampf(age / 0.30, 0.05, 1.0),
			Color(InfectedDangerGeometry.CREAM, opacity), 0.03)
		_dust(point, BurstRuntimeV1.RADIUS, age / 0.30, opacity)


func _draw_boss_impact() -> void:
	if world.encounter == null or not is_instance_valid(world.encounter.actor):
		return
	if world.encounter.actor.health <= 0.0:
		return
	if world.encounter.pump != null:
		var recovery: float = float(world.encounter.pump.state.recovery)
		if recovery > 0.0:
			var progress: float = 1.0 - recovery / PumpCharge.RECOVERY
			_dust(world.encounter.actor.position, PumpCharge.HALF_WIDTH, progress, 1.0 - progress)
	elif _boss_released_at >= 0.0 and _boss_radius > 0.0:
		var progress: float = (world.elapsed - _boss_released_at) / 0.30
		if progress >= 0.0 and progress < 1.0:
			InfectedDangerGeometry.rim(self, _boss_point, _boss_radius * maxf(0.05, progress),
				Color(InfectedDangerGeometry.CREAM, 1.0 - progress), 0.03)
			_dust(_boss_point, _boss_radius, progress, 1.0 - progress)


func _dust(point: Vector2, radius: float, progress: float, opacity: float) -> void:
	for index: int in range(8):
		var heading: Vector2 = Vector2.from_angle(float(index) * TAU / 8.0)
		var center: Vector2 = IsoSpace.to_view(point + heading * radius * progress * 0.7)
		center.y -= sin(progress * PI) * 5.0
		draw_circle(center, lerpf(1.5, 5.0, progress), Color(InfectedDangerGeometry.CREAM, opacity * 0.32), true, -1.0, true)


func _draw_hound(actor: FieldActor) -> void:
	if actor.enemy_behavior.state == "windup":
		var progress: float = 1.0 - actor.enemy_behavior.windup_remaining / NightHoundV1.WINDUP
		InfectedDangerGeometry.rim(self, actor.position, NightHoundV1.RANGE,
			InfectedDangerGeometry.AMBER, 0.05, progress)
	elif actor.visual._attack_clock > 0.14:
		var foot: Vector2 = IsoSpace.to_view(actor.position)
		var heading: Vector2 = actor.visual._facing
		var opacity: float = actor.visual._attack_clock / 0.30
		for side: float in [-1.0, 1.0]:
			var offset: Vector2 = heading.orthogonal() * side * 5.0
			draw_line(foot + offset - heading * 14.0, foot + offset,
				Color(InfectedDangerGeometry.CREAM, opacity * 0.7), 1.5, true)
