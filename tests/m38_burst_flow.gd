extends "res://tests/campaign_flow.gd"
## Controlled scope: copies the confirmed M38 common camp and uses one real
## signed industrial offer. Positions and time are controlled to isolate combat.

func _resume() -> void:
	_pure_boundaries()
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	if app.expedition == null:
		await _prepare_burst()
	else:
		await _resume_burst(app.expedition)


func _prepare_burst() -> void:
	var lined: bool = "--m38-burst-bare" not in OS.get_cmdline_user_args()
	await _tap(app.camp_scene.hotspots[&"weapons"])
	app.equip_power(SpecialPowers.SUPPRESSION, 0)
	app.equip_power(SpecialPowers.FREEZE, 1)
	app.equip_build_item(0, BuildItems.LINER if lined else "")
	_check(not app._progress_blocked, "controlled fixture uses confirmed camp loadout transactions")
	await _tap(app.loadout_panel.back_button)
	await _tap(app.camp_scene.hotspots[&"bus"])
	var offers: Array = app.mission_select.daily_offers
	var choice: int = offers.find_custom(func(offer: Dictionary) -> bool: return ContentWaveV1.eligible(offer))
	_check(choice >= 0, "common camp has a real eligible industrial offer")
	if choice < 0:
		return
	var world: Expedition = await _start(choice)
	if world == null or world.combat.burst == null:
		return
	world.elapsed = world.tuning.daylight_seconds * world.threat.rules.late_fraction + 0.125
	world.threat.update(world.elapsed, world.tuning.daylight_seconds, world.tuning.spawn_seconds)
	var direct: FieldActor = null
	for index: int in range(ThreatRules.ENEMY_CAP):
		world._spawn_enemy()
		for actor: FieldActor in world.enemies:
			if actor.enemy_behavior.kind in [EnemyRules.NORMAL, EnemyRules.RUSH]:
				direct = actor
				break
		if world.combat.burst.state.actor_id >= 0 and direct != null:
			break
	_check(world.combat.burst.state.actor_id >= 0, "original eligible spawn produces one burst actor")
	var source: FieldActor = world.combat._enemy(world, int(world.combat.burst.state.actor_id))
	_check(direct != null, "original spawn provides a normal or rush melee source")
	if source == null or direct == null:
		return
	var pair: Array[Vector2] = _clear_pair(world)
	_check(pair.size() == 3, "controlled positions use actual navigation and unobstructed world geometry")
	if pair.size() != 3 or world.survivors.size() < 2:
		return
	for actor: FieldActor in world.survivors:
		actor.cooldown = 1000.0
	source.position = pair[0]
	source.clear_order()
	var victim: FieldActor = world.survivors[0]
	victim.position = pair[1]
	victim.clear_order()
	var second: FieldActor = world.survivors[1]
	second.position = pair[2]
	second.clear_order()
	var melee: float = _direct_hit(world, direct, second, pair[0])
	_check(melee == world.tuning.enemy_damage, "original direct melee applies baseline damage")
	world.combat.burst.advance(world, 0.0)
	_check(world.combat.burst.state.phase == "windup", "actual legal close target starts one pulse warning")
	var suppressed: bool = world.request_power(0)
	var frozen: bool = world.request_power(1)
	_check(suppressed, "separate suppression activation is durable")
	_check(frozen, "second slot-independent freeze activation is durable")
	if not suppressed or not frozen:
		return
	_check(SpecialPowers.ability_remaining(world.powers, SpecialPowers.SUPPRESSION, world.elapsed) == 12.0 and world.power_frozen,
		"freeze and suppression are active at the same time with separate clocks")
	var remaining: float = float(world.combat.burst.state.remaining)
	world.combat.burst.advance(world, 0.2)
	_check(world.combat.burst.state.remaining == remaining, "frozen burst clock does not advance")
	var freeze_end: float = float(SpecialPowers.event_at(world.powers, 1).until)
	world.elapsed = freeze_end
	world.refresh_power_factors()
	_check(not world.power_frozen and SpecialPowers.ability_remaining(world.powers, SpecialPowers.SUPPRESSION, world.elapsed) > 0.0,
		"suppression remains active when the independent freeze expires")
	var reduced: float = _direct_hit(world, direct, second, pair[0])
	_check(reduced == melee * 0.5, "same direct attacker still lands the hit at half damage")
	world.elapsed += 0.2
	world.combat.burst.advance(world, 0.2)
	_check(is_equal_approx(world.combat.burst.state.remaining, remaining - 0.2), "unfrozen windup uses elapsed simulation")
	app.open_pause_menu()
	await _hold(2)
	var checkpoint: Dictionary = SortieSnapshot.capture(world)
	_write("burst-checkpoint.json", {"fingerprint":RecordEncoding.fingerprint(checkpoint),
		"remaining":world.combat.burst.state.remaining, "suppression":SpecialPowers.ability_remaining(world.powers, SpecialPowers.SUPPRESSION, world.elapsed),
		"source_id":world.combat.burst.state.actor_id, "victim":victim.member_id, "second":second.member_id,
		"direct_id":direct.actor_id, "melee":melee, "reduced":reduced, "lined":lined, "pid":OS.get_process_id()})
	app.suspend_sortie()
	await _hold(3)
	_check(app.expedition == null and app._requires_continue, "normal suspend commits burst windup and active suppression")


func _resume_burst(world: Expedition) -> void:
	world.set_process(false)
	world.set_physics_process(false)
	world.combat_feedback.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
	var path: String = output.get_base_dir().path_join("burst-first/burst-checkpoint.json")
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(expected is Dictionary and world.combat.burst != null, "restored world and prior controlled proof exist")
	if not expected is Dictionary or world.combat.burst == null:
		return
	var checkpoint: Dictionary = SortieSnapshot.capture(world)
	_check(expected.pid != OS.get_process_id() and expected.fingerprint == RecordEncoding.fingerprint(checkpoint),
		"different process reads the exact original frozen world")
	_check(is_equal_approx(float(expected.remaining), float(world.combat.burst.state.remaining)) \
		and is_equal_approx(float(expected.suppression), SpecialPowers.ability_remaining(world.powers, SpecialPowers.SUPPRESSION, world.elapsed)),
		"windup and suppression clocks restore independently")
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused:
		world.toggle_pause()
	var victim: FieldActor = world.search_member(int(expected.victim))
	var second: FieldActor = world.search_member(int(expected.second))
	var second_before: float = second.health
	_check(victim.take_damage(victim.health - 10.0), "controlled nonlethal injury passes original field damage gate")
	var prior: Dictionary = app.progress_session._transaction.recover()
	var seen: Dictionary = {"fired":false}
	app.progress_session.fault_hook = func(point: String) -> Error:
		if point == "before_record_write" and not seen.fired:
			seen.fired = true
			return ERR_CANT_CREATE
		return OK
	var release_after: float = float(world.combat.burst.state.remaining) + 0.001
	world.elapsed += release_after
	world.combat.burst.advance(world, release_after)
	_check(seen.fired and world.is_paused and victim.health == 10.0 and not world.pending_burst.is_empty(),
		"write failure preserves the original victim HP and pending world")
	if world.pending_burst.is_empty():
		app.progress_session.fault_hook = Callable()
		return
	var pending: Dictionary = world.pending_burst.duplicate(true)
	app.progress_session.fault_hook = Callable()
	var invalid: Dictionary = pending.duplicate(true)
	invalid.combat.burst.origin[0] += 800.0
	_check(BurstAuthorityV1.propose(invalid, prior.receipt).is_empty(), "moved origin cannot certify the pending release")
	world.toggle_pause()
	var published: Dictionary = app.progress_session._transaction.recover()
	_check(published.error == OK and not world.is_paused and victim.health == 0.0 and victim.permanent_death,
		"retry publishes pulse and original permanent death in one confirmation")
	if published.error != OK or published.receipt.get("burst", {}).is_empty():
		return
	_check(published.receipt.deaths.size() == prior.receipt.deaths.size() + 1 \
		and published.receipt.deaths.back().death.member_id == victim.member_id,
		"one stable BATTLE death fact is appended")
	var event: Dictionary = published.receipt.get("burst", {})
	var pulse_damage: float = 13.0 if expected.lined else 20.0
	_check(not event.is_empty() and event.source_id == expected.source_id and event.sequence == 1 \
		and event.hits.any(func(hit: Dictionary) -> bool: return hit.member_id == victim.member_id and hit.amount == pulse_damage),
		"ordered receipt binds the same source and expected pulse damage")
	_check(second_before - second.health == pulse_damage, "living second target receives the exact pulse damage")
	var duplicate: Dictionary = app.progress_session.accept_burst(pending)
	_check(duplicate.error == OK and duplicate.hash == published.hash,
		"duplicate request reads the existing release without another hit or append")
	world.elapsed = float(SpecialPowers.event_at(world.powers, 0).until)
	world.refresh_power_factors()
	var direct: FieldActor = world.combat._enemy(world, int(expected.direct_id))
	_check(direct != null, "same ordinary attacker survives suspend and pulse confirmation")
	if direct == null:
		return
	var restored: float = _direct_hit(world, direct, second, SortieSnapshot._vec(event.origin))
	_check(restored == float(expected.melee), "direct melee returns to its baseline at suppression expiry")
	_write("burst-proof.json", {"event":event, "receipt":published.hash, "dead":published.receipt.deaths.back(),
		"direct_damage":[expected.melee, expected.reduced, restored], "pulse_damage":pulse_damage})


func _clear_pair(world: Expedition) -> Array[Vector2]:
	for x: int in range(-160, 161, 16):
		for y: int in range(-160, 161, 16):
			var origin: Vector2 = world.layout.bus_door + Vector2(x, y)
			if not world.navigation.is_clear(origin):
				continue
			for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
				var target: Vector2 = origin + direction * 40.0
				if not world.navigation.is_clear(target) or not BurstRuntimeV1.reaches(origin, target, world.shot_obstacles):
					continue
				var second: Vector2 = origin - direction * 48.0
				if world.navigation.is_clear(second) and world.navigation._segment_is_clear(origin, second) \
						and BurstRuntimeV1.reaches(origin, second, world.shot_obstacles):
					return [origin, target, second]
	return []


func _direct_hit(world: Expedition, attacker: FieldActor, target: FieldActor, origin: Vector2) -> float:
	var before: float = target.health
	attacker.position = target.position.move_toward(origin, 20.0)
	attacker.cooldown = 0.0
	attacker.clear_order()
	world._update_combat()
	return before - target.health


func _pure_boundaries() -> void:
	var open: Array[ShotObstacle] = []
	var wall: Array[ShotObstacle] = [ShotObstacle.new(&"fixture-wall", Rect2(18.0, -5.0, 4.0, 10.0), true)]
	_check(BurstRuntimeV1.reaches(Vector2.ZERO, Vector2(68.0, 0.0), open), "pulse includes its 68-unit radius")
	_check(not BurstRuntimeV1.reaches(Vector2.ZERO, Vector2(68.1, 0.0), open), "pulse rejects a target beyond its radius")
	_check(not BurstRuntimeV1.reaches(Vector2.ZERO, Vector2(40.0, 0.0), wall), "projected shot wall occludes the pulse")
	var targets: Array[Dictionary] = [
		{"id":1, "foot":Vector2(40.0, 0.0), "alive":true, "available":true},
		{"id":2, "foot":Vector2(42.0, 5.0), "alive":true, "available":true},
		{"id":3, "foot":Vector2(20.0, 25.0), "alive":true, "available":true},
	]
	var hammer: Array[Dictionary] = CombatPatternsV1.melee_plan(CombatEquipment.HAMMER_ID, Vector2.ZERO, Vector2.RIGHT, targets, open, 54.0)
	_check(hammer.size() == 1 and hammer[0].id == 1, "hammer uses the narrow arc and commits one nearest legal target")
	_check(CombatPatternsV1.axe_plan(Vector2.ZERO, Vector2.RIGHT, targets, open).size() == 3, "axe retains its broader three-target arc")
	_check(CombatPatternsV1.melee_plan(CombatEquipment.HAMMER_ID, Vector2.ZERO, Vector2.RIGHT, targets, wall, 54.0).is_empty(), "hammer cannot strike through the wall")
	var powers: Dictionary = {"version":SpecialPowers.WAVE_VERSION, "loadout":{"slots":[SpecialPowers.SUPPRESSION]},
		"accepted":[{"slot":0, "at":3.0, "until":15.0}]}
	for kind: String in [EnemyRules.NORMAL, EnemyRules.RUSH, EnemyRules.HEAVY]:
		_check(CombatRuntime.direct_melee_damage(kind, 6.0, powers, 2.99) == 6.0 \
			and CombatRuntime.direct_melee_damage(kind, 6.0, powers, 3.0) == 3.0 \
			and CombatRuntime.direct_melee_damage(kind, 6.0, powers, 15.0) == 6.0, "direct melee 6→3→6 for " + kind)
	_check(CombatRuntime.direct_melee_damage(BurstRuntimeV1.KIND, 20.0, powers, 4.0) == 20.0, "suppression excludes burst")
