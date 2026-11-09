extends "res://tests/campaign_flow.gd"
## Controlled scope: copies the confirmed M38 common camp and uses one real
## signed industrial offer. Positions and time are controlled to isolate combat.

const LOST_ACK_FLAG: String = "--m38-burst-post-publish"

func _resume() -> void:
	_pure_boundaries()
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	if LOST_ACK_FLAG in OS.get_cmdline_user_args() and output.get_file() == "burst-recover":
		await _recover_published_burst(app.expedition)
		return
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
	if LOST_ACK_FLAG in OS.get_cmdline_user_args():
		await _capture_burst_warning(world, remaining)
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
	if LOST_ACK_FLAG in OS.get_cmdline_user_args():
		_publish_burst_without_ack(world, victim, second)
		return
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


func _capture_burst_warning(world: Expedition, remaining: float) -> void:
	var origin: Vector2 = SortieSnapshot._vec(world.combat.burst.state.origin)
	var saved_camera: Vector2 = world.camera.position
	var saved_size: Vector2i = viewport.size
	var warning: Label = world._hud._burst_warning
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1024, 576)]:
		viewport.size = size
		await _hold(3)
		world.camera.pan_by(origin - world.camera.position)
		world.camera.force_update_scroll()
		world._update_ui()
		world.queue_redraw()
		await _hold(2)
		var label_rect: Rect2 = warning.get_global_rect()
		var frame: Rect2 = viewport.get_visible_rect()
		var transform: Transform2D = world.get_global_transform_with_canvas()
		var radius: Vector2 = transform.get_scale() * BurstRuntimeV1.RADIUS
		var ring: Rect2 = Rect2(transform * origin - radius, radius * 2.0)
		var readouts: Array[Dictionary] = world._readouts.entries
		var clear: bool = readouts.size() == 3 and readouts.all(func(row: Dictionary) -> bool:
			return frame.encloses(row.rect) and not label_rect.intersects(row.rect))
		var dimensions: String = "%dx%d" % [size.x, size.y]
		_check(warning.is_visible_in_tree() and warning.text == "爆囊冲击 · %.1f 秒" % remaining
			and frame.encloses(label_rect) and frame.encloses(ring) and not label_rect.intersects(ring) and clear,
			"%s shows the countdown, warning ring and all three team readouts without covering the countdown" % dimensions)
		await _shot("burst-warning-" + dimensions)
	viewport.size = saved_size
	await _hold(3)
	world.camera.pan_by(saved_camera - world.camera.position)
	world.camera.force_update_scroll()
	world._update_ui()


func _publish_burst_without_ack(world: Expedition, victim: FieldActor, second: FieldActor) -> void:
	_check(world.living_count() == 3, "lost-ACK fixture begins with exactly three living actors")
	if world.living_count() != 3:
		return
	var survivor: FieldActor = world.survivors.filter(func(actor: FieldActor) -> bool: return actor != victim and actor != second)[0]
	var origin: Vector2 = SortieSnapshot._vec(world.combat.burst.state.origin)
	_check(not BurstRuntimeV1.reaches(origin, survivor.position, world.shot_obstacles), "third actor is out of the pulse")
	_check(victim.take_damage(victim.health - 10.0) and second.take_damage(second.health - 10.0),
		"both intended victims reach 10 HP through the existing nonlethal damage gate")
	var prior: Dictionary = app.progress_session._transaction.recover()
	_check(prior.error == OK and prior.receipt.burst.is_empty(), "no burst has been published before the fault")
	if prior.error != OK:
		return
	var lost_ack: Dictionary = {"count":0}
	app.progress_session.fault_hook = func(point: String) -> Error:
		if point == "after_record_publish":
			lost_ack.count += 1
			return ERR_CANT_CREATE
		return OK
	var delta: float = float(world.combat.burst.state.remaining) + 0.001
	world.elapsed += delta
	world.combat.burst.advance(world, delta)
	app.progress_session.fault_hook = Callable()
	_check(lost_ack.count == 1 and world.is_paused and not world.pending_burst.is_empty()
		and victim.health == 10.0 and second.health == 10.0 and world.living_count() == 3,
		"publication loses its ACK before claim and applies neither hit to the live actors")
	_check(world._hud._burst_warning.is_visible_in_tree() and world._hud._burst_warning.text == "爆囊冲击 · 确认中",
		"pending release shows confirmation status in the warning")
	var published: Dictionary = app.progress_session._transaction.recover()
	var receipt: Dictionary = published.get("receipt", {})
	var event: Dictionary = receipt.get("burst", {})
	_check(published.error == OK and receipt.get("phase") == "SUSPEND_READY"
		and receipt.get("revision", -1) == int(prior.receipt.revision) + 1
		and event.get("source_id") == world.combat.burst.state.actor_id and event.get("sequence") == 1
		and not event.is_empty(), "one durable release is available for a new process to claim")
	if event.is_empty():
		return
	var victims: Array[int] = [victim.member_id, second.member_id]
	victims.sort()
	var death_batch: Array = receipt.deaths.slice(prior.receipt.deaths.size())
	_check(death_batch.size() == 2 and event.hits.size() == 2, "release contains exactly two hits and two new deaths")
	if death_batch.size() != 2 or event.hits.size() != 2:
		return
	for index: int in range(victims.size()):
		var death: Dictionary = death_batch[index].death
		var hit: Dictionary = event.hits[index]
		_check(death.member_id == victims[index] and death.cause == "BATTLE" and death.transaction_id == receipt.transaction_id
			and death.death_id == "%s:death:%d" % [receipt.base.profile_id, victims[index]]
			and hit.member_id == victims[index] and hit.before == 10.0 and hit.after == 0.0,
			"stable member order binds one lethal hit and BATTLE death to member %d" % victims[index])
	_write("lost-ack.json", {"pid":OS.get_process_id(), "published_hash":published.hash,
		"world_hash":receipt.envelope.world_hash, "transaction_id":receipt.transaction_id,
		"snapshot_hash":RecordEncoding.fingerprint(receipt.envelope.world),
		"event_id":event.id, "event_hash":RecordEncoding.fingerprint(event),
		"death_hash":RecordEncoding.fingerprint({"deaths":receipt.deaths}),
		"death_batch":death_batch, "victims":victims, "survivor":survivor.member_id, "survivor_health":survivor.health})
	# End this process with the release still available for normal Continue.


func _recover_published_burst(world: Expedition) -> void:
	var path: String = output.get_base_dir().path_join("burst-publish/lost-ack.json")
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(world != null and world.combat.burst != null and expected is Dictionary,
		"normal Continue restores the released world from the preceding lost-ACK process")
	if world == null or world.combat.burst == null or not expected is Dictionary:
		return
	world.set_process(false)
	world.set_physics_process(false)
	world.combat_feedback.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
	var claimed: Dictionary = app.progress_session._transaction.recover()
	var receipt: Dictionary = claimed.get("receipt", {})
	_check(expected.pid != OS.get_process_id() and receipt.get("phase") == "RESUME_CLAIMED"
		and receipt.get("previous_hash") == expected.published_hash and not world.suspend_sealed
		and receipt.get("envelope", {}).get("world_hash") == expected.world_hash
		and RecordEncoding.fingerprint(SortieSnapshot.capture(world)) == expected.snapshot_hash,
		"fresh process claims the exact published world once")
	var burst: Dictionary = world.combat.burst.state
	_check(burst.phase == "released" and burst.event.get("id") == expected.event_id
		and RecordEncoding.fingerprint(burst.event) == expected.event_hash
		and RecordEncoding.fingerprint({"deaths":receipt.get("deaths", [])}) == expected.death_hash,
		"release and its death records survive exactly without reapplying damage")
	_check(not world._hud._burst_warning.visible, "a restored release has no pending warning")
	for member_id: Variant in expected.victims:
		var victim: FieldActor = world.search_member(int(member_id))
		_check(victim != null and victim.health == 0.0 and victim.permanent_death,
			"restored actor %d is already permanently down" % int(member_id))
	var survivor: FieldActor = world.search_member(int(expected.survivor))
	_check(survivor != null and world.living_count() == 1 and survivor.health == expected.survivor_health,
		"only the original untouched survivor can board")
	var settled_before: int = app.settled_sorties
	await _tap(app.pause_menu.buttons[0])
	if world.is_paused:
		world.toggle_pause()
	await _extract(world)
	_check(world.living_count() == 1 and not app._pending_settlement.is_empty()
		and not events.any(func(event: Dictionary) -> bool: return event.kind in ["burst_released", "burst_hit"]),
		"bus extraction preserves the surviving actor and never releases the pulse again")
	var token: Dictionary = app.progress_session.token.duplicate(true)
	await _tap(app.get_node("Interface/Screen/Result/Continue"))
	var camp: Dictionary = app.camp_snapshot()
	var committed: Dictionary = app.progress_session._transaction.recover()
	var final_receipt: Dictionary = committed.get("receipt", {})
	var repeated: Dictionary = app.progress_session._transaction.commit(token)
	_check(committed.error == OK and final_receipt.get("phase") == "COMMITTED"
		and camp.settled_sorties == settled_before + 1 and camp.last_settlement_id == expected.transaction_id
		and RecordEncoding.fingerprint(final_receipt.get("burst", {})) == expected.event_hash
		and RecordEncoding.fingerprint({"deaths":final_receipt.get("deaths", [])}) == expected.death_hash
		and repeated.error == OK and repeated.hash == committed.hash and TransactionReceipt.same(camp, app.camp_snapshot()),
		"original return and its repeated confirmation preserve one release, two deaths and one settlement")
	_write("recovered-return.json", {"pid":OS.get_process_id(), "claimed_hash":claimed.get("hash", ""),
		"committed_hash":committed.get("hash", ""), "repeat_hash":repeated.get("hash", ""),
		"event":final_receipt.get("burst", {}), "deaths":final_receipt.get("deaths", []), "settled_sorties":camp.settled_sorties})


func _clear_pair(world: Expedition) -> Array[Vector2]:
	var keep_third_safe: bool = LOST_ACK_FLAG in OS.get_cmdline_user_args() and world.survivors.size() == 3
	for x: int in range(-160, 161, 16):
		for y: int in range(-160, 161, 16):
			var origin: Vector2 = world.layout.bus_door + Vector2(x, y)
			if not world.navigation.is_clear(origin):
				continue
			if keep_third_safe and BurstRuntimeV1.reaches(origin, world.survivors[2].position, world.shot_obstacles):
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
