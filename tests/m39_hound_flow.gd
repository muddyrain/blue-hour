extends "res://tests/campaign_flow.gd"
## Controlled Mac fixture. Opens a signed ordinary action and fixes only field
## inputs so spawn, attack, death, and resume exercise their normal owners.

var spawns: Array[Dictionary] = []


func _resume() -> void:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	match output.get_file():
		"hound-first":
			await _first()
		"hound-resume":
			await _resume_windup(app.expedition)
		"hound-defeated":
			await _resume_defeat(app.expedition)
		_:
			_check(false, "select hound-first, hound-resume or hound-defeated")


func _first() -> void:
	var camp: Dictionary = app.camp_snapshot()
	var powers: Dictionary = camp.journey.build.powers
	if SpecialPowers.FREEZE not in powers.slots:
		_check(SpecialPowers.FREEZE in powers.owned, "common isolated camp owns freeze")
		if SpecialPowers.FREEZE not in powers.owned:
			return
		await _tap(app.camp_scene.hotspots[&"weapons"])
		app.equip_power(SpecialPowers.FREEZE, 0)
		await _tap(app.loadout_panel.back_button)
	await _tap(app.camp_scene.hotspots[&"bus"])
	var offers: Array = app.mission_select.daily_offers
	var choice: int = offers.find_custom(func(offer: Dictionary) -> bool: return NightHoundV1.enabled(offer))
	_check(choice >= 0, "camp has a signed eligible industrial action")
	if choice < 0:
		return
	var world: Expedition = await _start(choice)
	if world == null:
		return
	_observe_spawns(world)
	for member: FieldActor in world.survivors:
		member.cooldown = 1000.0
	world._spawn_enemy()
	_set_clock(world, world.tuning.daylight_seconds * world.threat.rules.late_fraction + 0.125)
	for index: int in range(3):
		world._spawn_enemy()
	var day_spawned: bool = spawns.any(func(row: Dictionary) -> bool:
		return row.reason == "spawned" and row.stage == ThreatDirector.Stage.CALM)
	var dusk_spawned: bool = spawns.any(func(row: Dictionary) -> bool:
		return row.reason == "spawned" and row.stage == ThreatDirector.Stage.LATE)
	_check(_hound_count(world) == 0 and day_spawned and dusk_spawned,
		"successful daytime and dusk spawns never contain a hound")
	_set_clock(world, world.tuning.daylight_seconds + 0.125)
	var before: int = world._spawn_count
	var original_cap: int = world.threat.rules.enemy_cap
	world.threat.rules.enemy_cap = world.enemies.size()
	world._spawn_clock = 0.0
	world.step(0.001)
	world.threat.rules.enemy_cap = original_cap
	_check(world._spawn_count == before and spawns.back().reason == "capacity", "full spawn budget leaves the next identity unused")
	var activities: Array[FieldActor.Activity] = []
	for member: FieldActor in world.survivors:
		activities.append(member.activity)
		member.activity = FieldActor.Activity.SEARCHING
	var blocked: Dictionary = world._spawn_enemy()
	for index: int in range(world.survivors.size()):
		world.survivors[index].activity = activities[index]
	_check(blocked.reason == "no_safe_point" and world._spawn_count == before and _hound_count(world) == 0,
		"no legal target entrance leaves the next identity and hound quota unused")
	var dog: FieldActor = null
	for index: int in range(original_cap - world.enemies.size()):
		var attempt: Dictionary = world._spawn_enemy()
		if attempt.reason == "spawned" and spawns.back().get("enemy_type") == NightHoundV1.KIND:
			dog = world.combat._enemy(world, int(attempt.enemy_id))
			break
	_check(dog != null and _hound_count(world) == 1, "first eligible ordinary success reserves one hound")
	if dog == null:
		return
	_check(dog.health == 32.0 and dog.speed == 64.0 and spawns.back().legal
		and dog.enemy_behavior.spawn_stage == ThreatDirector.Stage.NIGHT
		and CombatEnemyRules.pick(world.sortie_id, dog.actor_id, dog.enemy_behavior.spawn_stage) == EnemyRules.NORMAL,
		"original legal night spawn records the underlying ordinary roll, 32 HP and speed 64")
	_write("hound-spawns.json", {"action":world.supply.generated.id, "map":String(world.layout.id), "spawns":spawns})
	var victim: FieldActor = world.survivors[0]
	var point: Vector2 = _contact_point(world, victim)
	_check(point.is_finite(), "actual street geometry provides one clear melee pair")
	if not point.is_finite():
		return
	dog.position = point
	dog.clear_order()
	world._update_combat()
	_check(_winding(dog, victim) and dog.enemy_behavior.windup_remaining == NightHoundV1.WINDUP,
		"hound crouches for its original 0.45-second lock on one target")
	var slot: int = 0 if SpecialPowers.equipped_at(world.powers, 0) == SpecialPowers.FREEZE else 1
	var freeze: bool = world.request_power(slot)
	_check(freeze and world.power_frozen, "ordinary freeze commits while the hound is winding up")
	if not freeze:
		return
	var freeze_event: Dictionary = SpecialPowers.event_at(world.powers, slot)
	var frozen_health: float = victim.health
	world.step(0.2)
	var frozen_remaining: float = dog.enemy_behavior.windup_remaining
	_check(world.power_frozen and dog.position == point and _winding(dog, victim)
		and frozen_remaining == NightHoundV1.WINDUP and victim.health == frozen_health,
		"real frozen step holds feet, target, windup and health")
	_set_clock(world, float(freeze_event.until))
	world.refresh_power_factors()
	_attack_step(world, 0.125)
	_check(not world.power_frozen and _winding(dog, victim)
		and is_equal_approx(dog.enemy_behavior.windup_remaining, NightHoundV1.WINDUP - 0.125),
		"thaw resumes the same windup without hitting early")
	await _suspend(world, "hound-checkpoint.json", {"id":dog.actor_id, "target":victim.member_id,
		"point":[dog.position.x, dog.position.y], "remaining":dog.enemy_behavior.windup_remaining,
		"frozen_remaining":frozen_remaining, "freeze":freeze_event})


func _resume_windup(world: Expedition) -> void:
	var proof: Dictionary = _checkpoint(world, "hound-first/hound-checkpoint.json")
	if proof.is_empty():
		return
	var dog: FieldActor = world.combat._enemy(world, int(proof.id))
	var victim: FieldActor = world.search_member(int(proof.target))
	_check(dog != null and victim != null and _winding(dog, victim)
		and dog.position == SortieSnapshot._vec(proof.point) and dog.enemy_behavior.windup_remaining == proof.remaining,
		"restored hound keeps its identity, feet, target and exact windup")
	if dog == null or victim == null:
		return
	await _unpause(world)
	var starting_health: float = victim.health
	_attack_step(world, float(proof.remaining) + 0.001)
	_attack_step(world, 0.0)
	_check(starting_health - victim.health == NightHoundV1.DAMAGE and _hits(dog) == 1
		and is_equal_approx(dog.cooldown, NightHoundV1.INTERVAL), "resumed windup bites once for 5 HP and enters the 0.90-second interval")
	var injured: float = victim.health
	var origin: Vector2 = victim.position
	_rearm(world, dog)
	_check(_winding(dog, victim), "range comparison begins with the same locked target")
	var away: Vector2 = _escape_point(world, dog.position)
	_check(away.is_finite(), "actual street geometry provides a reachable outside point")
	if not away.is_finite():
		return
	victim.position = away
	_attack_step(world, NightHoundV1.WINDUP + 0.001)
	_check(away.distance_to(dog.position) >= NightHoundV1.RANGE and victim.health == injured
		and _hits(dog) == 1 and _cancelled(dog) == 1, "leaving the locked range cancels the bite with no damage")
	victim.position = origin
	_rearm(world, dog)
	_check(_winding(dog, victim), "wall comparison begins with the same locked target")
	var middle: Vector2 = dog.position.lerp(victim.position, 0.5)
	world.shot_obstacles.append(ShotObstacle.new(&"m39-fixture-wall", Rect2(middle - Vector2(2, 2), Vector2(4, 4)), true))
	var blocked: bool = not dog.enemy_behavior.legal(world, dog, victim, NightHoundV1.RANGE)
	_attack_step(world, NightHoundV1.WINDUP + 0.001)
	world.shot_obstacles.pop_back()
	_check(blocked and victim.health == injured and _hits(dog) == 1 and _cancelled(dog) == 2,
		"same target behind a controlled shot obstacle receives no bite")
	_rearm(world, dog)
	_check(_winding(dog, victim), "third windup starts before the original weapon hits")
	# Use the original ranged commit with an existing survivor's weapon. No XP or
	# death state is injected, and the bite never has a chance to apply afterward.
	for index: int in range(5):
		if dog.health <= 0:
			break
		victim.cooldown = 0.0
		var shot: AttackRules.Decision = world.evaluate_attack(victim, dog)
		if not shot.can_fire or (victim.magazine != null and not victim.magazine.can_fire()):
			break
		world._fire_ranged(victim, dog, shot)
	victim.cooldown = 1000.0
	_attack_step(world, NightHoundV1.WINDUP + 0.001)
	_check(dog.health == 0.0 and world.combat._enemy(world, dog.actor_id) == null and _hits(dog) == 1
		and victim.health == injured and _hound_count(world) == 1,
		"ordinary weapon defeat cancels the pending bite but retains the spawn identity")
	_write("hound-attacks.json", {"member":victim.member_id, "before":starting_health, "after":victim.health, "events":events})
	await _suspend(world, "hound-defeat.json", {"id":dog.actor_id})


func _resume_defeat(world: Expedition) -> void:
	var proof: Dictionary = _checkpoint(world, "hound-resume/hound-defeat.json")
	if proof.is_empty():
		return
	var id: int = int(proof.id)
	_check(world.combat._enemy(world, id) == null and _hound_count(world) == 1
		and world.combat.spawns.get(str(id), {}).get("kind") == NightHoundV1.KIND,
		"defeated hound is absent while the exact consumed spawn persists")
	await _unpause(world)
	_observe_spawns(world)
	var ordinary: Dictionary = {}
	for index: int in range(world.threat.rules.enemy_cap - world.enemies.size()):
		var next: Dictionary = world._spawn_enemy()
		if next.reason == "spawned" and CombatEnemyRules.pick(world.sortie_id, int(next.enemy_id), int(world.threat.stage)) == EnemyRules.NORMAL:
			ordinary = spawns.back()
			break
	_check(ordinary.get("enemy_type") == EnemyRules.NORMAL and _hound_count(world) == 1
		and world.combat._enemy(world, id) == null, "a successful normal roll remains ordinary after the defeated hound restores")
	_write("hound-quota.json", {"id":id, "count":_hound_count(world), "spawn":ordinary})
	await _extract(world)
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	_check(app.camp_scene.is_visible_in_tree() and not app._progress_blocked,
		"defeated-hound restore confirms through the original return flow")


func _suspend(world: Expedition, filename: String, evidence: Dictionary) -> void:
	app.open_pause_menu()
	await _hold(2)
	var checkpoint: Dictionary = SortieSnapshot.capture(world)
	_check(not checkpoint.is_empty(), "controlled live world captures the requested checkpoint")
	if checkpoint.is_empty():
		return
	evidence.merge({"pid":OS.get_process_id(), "fingerprint":RecordEncoding.fingerprint(checkpoint)})
	_write(filename, evidence)
	app.suspend_sortie()
	await _hold(3)
	_check(app.expedition == null and app._requires_continue, "original safe suspend returns to continue screen")


func _checkpoint(world: Expedition, path: String) -> Dictionary:
	var proof: Variant = JSON.parse_string(FileAccess.get_file_as_string(output.get_base_dir().path_join(path)))
	_check(world != null and proof is Dictionary, "normal Continue restores the previous process fixture")
	if world == null or not proof is Dictionary:
		return {}
	world.set_process(false)
	world.set_physics_process(false)
	world.combat_feedback.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
	_check(proof.pid != OS.get_process_id() and proof.fingerprint == RecordEncoding.fingerprint(SortieSnapshot.capture(world)),
		"separate process restores the exact saved world fingerprint")
	return proof


func _unpause(world: Expedition) -> void:
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused:
		world.toggle_pause()


func _observe_spawns(world: Expedition) -> void:
	world.spawn_resolved.connect(func(event: Dictionary) -> void: spawns.append(event.duplicate(true)))


func _set_clock(world: Expedition, elapsed: float) -> void:
	world.elapsed = elapsed
	world.threat.update(elapsed, world.tuning.daylight_seconds, world.tuning.spawn_seconds)


func _attack_step(world: Expedition, seconds: float) -> void:
	_set_clock(world, world.elapsed + seconds)
	world._update_enemy_behaviors(seconds)
	world._update_combat()


func _rearm(world: Expedition, dog: FieldActor) -> void:
	dog.advance(NightHoundV1.INTERVAL + 0.001, false, false)
	_attack_step(world, 0.0)


func _contact_point(world: Expedition, victim: FieldActor) -> Vector2:
	for index: int in range(8):
		var point: Vector2 = victim.position + Vector2.RIGHT.rotated(index * TAU / 8.0) * 25.0
		if not world.navigation.is_clear(point) or world.survivors.any(func(member: FieldActor) -> bool:
			return member != victim and member.position.distance_to(point) <= 25.0):
			continue
		var source: AttackRules.Combatant = AttackRules.Combatant.new(point, true, true, true)
		if AttackRules.evaluate(source, world._combatant(victim), point + Vector2.UP * AttackRules.HIT_HEIGHT,
				NightHoundV1.RANGE, 0.0, world.shot_obstacles).targetable \
				and AttackRules.evaluate(world._combatant(victim), source, victim.position + victim.visual.aimed_shot_offset(point - victim.position),
					victim.weapon_definition.shot_range, 0.0, world.shot_obstacles).targetable:
			return point
	return Vector2.INF


func _escape_point(world: Expedition, origin: Vector2) -> Vector2:
	for index: int in range(8):
		var point: Vector2 = origin + Vector2.RIGHT.rotated(index * TAU / 8.0) * 95.0
		if world.navigation.is_clear(point) and world.navigation.path_between(origin, point).size() > 1:
			return point
	return Vector2.INF


func _winding(dog: FieldActor, victim: FieldActor) -> bool:
	return dog.enemy_behavior.state == "windup" and dog.enemy_behavior.target_id == victim.member_id


func _hits(dog: FieldActor) -> int:
	return events.filter(func(event: Dictionary) -> bool:
		return event.kind == "hit" and event.get("enemy_id") == dog.actor_id).size()


func _cancelled(dog: FieldActor) -> int:
	return events.filter(func(event: Dictionary) -> bool:
		return event.kind == "enemy_cancel" and event.get("enemy_id") == dog.actor_id).size()


func _hound_count(world: Expedition) -> int:
	return world.combat.spawns.values().filter(func(source: Dictionary) -> bool: return source.kind == NightHoundV1.KIND).size()
