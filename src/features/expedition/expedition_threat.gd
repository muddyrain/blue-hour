class_name ExpeditionThreat
extends RefCounted

var expedition: Expedition


func _init(owner: Expedition) -> void:
	expedition = owner


func _spawn_enemy(forced_kind: String = "", pressure_point: Vector2 = Vector2.INF, provenance: Dictionary = {}) -> Dictionary:
	var point: Vector2 = expedition._threat._safe_spawn_point(pressure_point)
	if not point.is_finite():
		expedition._threat._record_spawn(&"no_safe_point", point, -1, provenance)
		return {"reason":"no_safe_point","enemy_id":-1}
	var enemy: FieldActor = expedition._make_actor(true, expedition._spawn_count, point,{},forced_kind)
	expedition.enemies.append(enemy)
	expedition._spawn_count += 1
	if expedition.combat.screamer != null and enemy.enemy_behavior.kind == ScreamerPolicyV1.KIND:
		expedition.combat.screamer.spawned(expedition, enemy)
	if expedition.combat.burst != null and enemy.enemy_behavior.kind == BurstRuntimeV1.KIND:
		expedition.combat.burst.spawned(expedition, enemy)
	expedition._threat._record_spawn(&"spawned", point, enemy.actor_id, provenance)

	return {"reason":"spawned","enemy_id":enemy.actor_id}


func _spawn_screamer_batch(event: Dictionary) -> void:
	# Insert the whole batch before notifying listeners. It never modifies the ambient clock.
	for row: Dictionary in event.spawned:
		var point: Vector2 = SortieSnapshot._vec(row.point)
		var enemy: FieldActor = expedition._make_actor(true, int(row.enemy_id), point, {}, EnemyRules.NORMAL)
		expedition.enemies.append(enemy)
	expedition._spawn_count += event.spawned.size()
	expedition._spawn_attempts += event.spawned.size()
	for row: Dictionary in event.spawned:
		expedition._threat._record_spawn(&"spawned", SortieSnapshot._vec(row.point), int(row.enemy_id),
			{"source":"screamer", "source_id":event.source_id, "event_id":event.event_id, "entrance":row.entrance}, false)


func _safe_spawn_point(pressure_point: Vector2 = Vector2.INF) -> Vector2:
	var candidates: Array[Vector2] = []
	for index: int in range(expedition.layout.enemy_points.size()):
		candidates.append(expedition.layout.enemy_points[(expedition._spawn_attempts + index) % expedition.layout.enemy_points.size()])
	var bounds: Rect2 = expedition.layout.world_bounds.grow(-ThreatRules.EDGE_MARGIN)
	for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		candidates.append(Vector2(lerpf(bounds.position.x, bounds.end.x, fraction), bounds.position.y))
		candidates.append(Vector2(lerpf(bounds.position.x, bounds.end.x, fraction), bounds.end.y))
		candidates.append(Vector2(bounds.position.x, lerpf(bounds.position.y, bounds.end.y, fraction)))
		candidates.append(Vector2(bounds.end.x, lerpf(bounds.position.y, bounds.end.y, fraction)))
	if pressure_point.is_finite():
		candidates.sort_custom(func(a: Vector2,b: Vector2) -> bool:return a.distance_squared_to(pressure_point)<b.distance_squared_to(pressure_point))
	var visible: Rect2 = expedition.visible_world_rect().grow(expedition.threat.rules.screen_margin)
	var occupied: Array[Vector2] = []
	for enemy: FieldActor in expedition.enemies:
		occupied.append(enemy.position)
	for point: Vector2 in candidates:
		if pressure_point.is_finite() and point.distance_to(pressure_point)<expedition.threat.rules.party_distance:
			continue
		var nearest: FieldActor = expedition._threat._nearest_target_from_point(point)
		if nearest != null and expedition.threat.rules.spawn_point_legal(point, visible, expedition.navigation, nearest.position, occupied):
			return point
	return Vector2.INF


func _nearest_target_from_point(point: Vector2) -> FieldActor:
	var nearest: FieldActor
	var distance: float = INF
	for actor: FieldActor in expedition.survivors:
		if actor.activity in [FieldActor.Activity.DOWN, FieldActor.Activity.SEARCHING]:
			continue
		var candidate: float = point.distance_squared_to(actor.position)
		if candidate < distance:
			distance = candidate
			nearest = actor
	return nearest


func _record_spawn(reason: StringName, point: Vector2, enemy_id: int = -1,
		provenance: Dictionary = {}, count_attempt: bool = true) -> void:
	expedition._spawn_attempts += int(count_attempt)
	var event: Dictionary = expedition.threat_status()
	var party_points: Array[Vector2] = []
	var enemy_points: Array[Vector2] = []
	for actor: FieldActor in expedition.survivors:
		if actor.activity not in [FieldActor.Activity.DOWN, FieldActor.Activity.SEARCHING]:
			party_points.append(actor.position)
	for enemy: FieldActor in expedition.enemies:
		if enemy.actor_id != enemy_id:
			enemy_points.append(enemy.position)
	event.merge({"reason":String(reason), "enemy_id":enemy_id,
		"point":[point.x, point.y] if point.is_finite() else [],
		"visible_rect":expedition.visible_world_rect(), "party_points":party_points, "enemy_points":enemy_points,
		"legal":expedition.navigation.is_clear(point) if point.is_finite() else false})
	if enemy_id>=0:
		for actor: FieldActor in expedition.enemies:
			if actor.actor_id==enemy_id:
				event.enemy_type = actor.enemy_behavior.kind
				event.enemy_health = actor.health
				event.enemy_speed = actor.speed
	event.merge(provenance, true)
	expedition.spawn_resolved.emit(event)


func _update_enemy_paths(idle_only: bool = false) -> void:
	if expedition.power_frozen: return
	for enemy: FieldActor in expedition.enemies:
		if (expedition.combat_mode() and expedition.combat.holds(enemy)) or (expedition.encounter!=null and expedition.encounter.holds(enemy)) or (enemy.enemy_behavior!=null and enemy.enemy_behavior.state=="windup"):
			continue
		var target: FieldActor = expedition._nearest_target(enemy, expedition.survivors, INF)
		if target == null or expedition._hold_enemy_approach(enemy):
			enemy.clear_order()
		elif not idle_only or (enemy.activity == FieldActor.Activity.IDLE and enemy.position.distance_to(target.position)>FieldContacts.RECHASE):
			enemy.command_path(expedition.navigation.path_between(enemy.position, target.position))


func _hold_enemy_approach(enemy: FieldActor) -> bool:
	var target: FieldActor = expedition._nearest_target(enemy,expedition.survivors,FieldContacts.APPROACH)
	if target != null and expedition.navigation._segment_is_clear(enemy.position,target.position):
		enemy.clear_order()
		return true
	return false


func threat_status() -> Dictionary:
	var state: Dictionary = expedition.threat.snapshot()
	state.merge({"enabled":true, "elapsed":expedition.elapsed, "spawned":expedition._spawn_count,
		"attempts":expedition._spawn_attempts, "next_spawn":expedition._spawn_clock, "active_enemies":expedition.enemies.size(),
		"cap":expedition.threat.rules.enemy_cap,
		"overtime":maxf(0.0,expedition.elapsed - expedition.tuning.daylight_seconds)})
	return state


func _trigger_airdrop() -> void:
	if expedition.task_event.started:
		return
	expedition._request_task_wave(expedition.search_site(&"cash"), int(TaskActions.PARAMETERS.reinforcements))
	expedition._show_notice("武器箱开工 · 增援接近；拿到武器即可集合归航。" if expedition.supply.generated.has("rare_policy")
		else "空投信标已启动 · 留意来袭；回收后可直接集合归航。")


func _request_task_wave(site: Expedition.SearchSite, requests: int, provenance: Dictionary = {}) -> void:
	expedition.task_event.started = true
	for index: int in range(requests):
		if expedition.enemies.size() >= expedition.threat.rules.enemy_cap:
			expedition._threat._record_spawn(&"capacity", Vector2.INF, -1, provenance)
			expedition.task_event.resolutions.append({"reason":"capacity","enemy_id":-1})
		else:
			expedition.task_event.resolutions.append(expedition._spawn_enemy(EnemyRules.NORMAL, site.door, provenance))
