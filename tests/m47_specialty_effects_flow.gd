extends "res://tests/m47_run_replay_flow.gd"
## Native checks. Directed wounds and an isolated cooldown interval use original support receipts.


func _journey() -> void:
	var phase_name: String = output.get_file()
	if phase_name in ["q-equipped", "q-stock"]:
		if not await _new_trip("support"):
			return
		if phase_name == "q-stock" and not _edit({"kind":"build_slot", "member_id":0, "value":""}):
			return
		var field: Expedition = await _ordinary_supply()
		if field != null:
			await _q_probe(field)
		return
	var plan_name: String = "support" if output.get_file() == "support-win" else "firepower"
	if not await _new_trip(plan_name):
		return
	await _finish_campaign("m47-" + plan_name)
	var progress: Dictionary = app.progress_session.catalog_state()
	_check(progress.error == OK and progress.specialties.get(plan_name) == 2,
		"two real investigation returns and the pump win unlock the selected specialty")
	_write("specialty-progress.json", progress)


func _investigate() -> bool:
	if output.get_file() == "support-win" and app.camp_snapshot().journey.campaign.clues.size() == 1:
		if not _edit({"kind":"build_slot", "member_id":0, "value":""}):
			return false
	return await super._investigate()


func _start(slot: int) -> Expedition:
	var world: Expedition = await super._start(slot)
	if world != null and output.get_file() == "support-win" and world.supply.generated.has("investigation"):
		await _q_probe(world)
	return world


func _q_probe(world: Expedition) -> void:
	var equipped: bool = BuildItems.AID_KIT in world.supply.generated.build.slots
	var actor: FieldActor = world.search_member(1)
	var clipped: float = 0.0
	var cooldown_edge: float = 0.0
	if equipped:
		_check(actor.health == actor.max_health and actor.take_damage(8.0), "directed starter wound is eight HP")
		world._update_ui()
		await _tap(world.support_panel.heal_button)
		var accepted: Array = world.basic_support.snapshot().accepted
		_check(accepted.size() == 1, "clipped Q has one original support receipt")
		if accepted.size() != 1:
			return
		clipped = float(accepted.back().facts.amount)
		_check(clipped == 8.0 and actor.health == actor.max_health, "equipped Q clips to exactly eight missing HP")
		_wound_for_q(actor)
		var next_spawn: float = world._spawn_clock
		world._spawn_clock = 31.0
		await _until(world, func() -> bool: return world.basic_support.remaining("heal") < 0.05)
		cooldown_edge = world.basic_support.remaining("heal")
		_check(cooldown_edge > 0.0 and not world.request_heal(), "positive Q cooldown rejects before the boundary")
		await _until(world, func() -> bool: return world.basic_support.ready("heal"))
		world._spawn_clock = next_spawn
	else:
		_wound_for_q(actor)
	var used: bool = world.request_heal()
	_check(used, "Q publishes through the original support transaction")
	if not used:
		return
	var accepted: Array = world.basic_support.snapshot().accepted
	var facts: Dictionary = accepted.back().facts
	_check(facts.amount == (48.0 if equipped else 40.0) and world.basic_support.remaining("heal") == 30.0,
		"Q uses the equipped or stock cap and the unchanged cooldown")
	var saved: Dictionary = app.progress_session._transaction.recover()
	_check(TransactionReceipt.same(saved.receipt.support.back().facts, facts) and not world.request_heal(),
		"accepted Q HP is durable and a repeat during cooldown cannot heal")
	_write("q-%s.json" % ("equipped" if equipped else "stock"), {"action":world.supply.generated.id,
		"equipped":equipped, "clipped":clipped, "facts":facts, "edge_before":cooldown_edge,
		"cooldown_after":world.basic_support.remaining("heal"), "receipt":saved.hash,
		"scope":"DIRECTED_WOUNDS_AND_SPAWN_TIMING"})


func _wound_for_q(actor: FieldActor) -> void:
	var desired: float = actor.max_health - 64.0
	if actor.health > desired:
		_check(actor.take_damage(actor.health - desired), "directed wound uses the original damage gate")


func _resume() -> void:
	match output.get_file():
		"radio-before":
			await _radio_before()
		"reload-prepare":
			await _reload_prepare()
		"reload-baseline", "reload-before":
			if await _continue_trip():
				await _reload_before(output.get_file() == "reload-before")
		"radio-after", "reload-after":
			if await _continue_trip():
				await _effects_after(output.get_file() == "radio-after")


func _continue_trip() -> bool:
	await _tap(app._continue_button)
	if app._hunger_confirmation.visible:
		await _tap(app._hunger_confirmation.get_ok_button())
	_check(not app._progress_blocked, "profile continues through the original title control")
	return not app._progress_blocked


func _recover_specialty(plan_name: String, item: String, special: bool) -> bool:
	if not await _new_trip(plan_name):
		return false
	_check(item in OpeningBuild.eligible(app.camp_snapshot()), "the new journey freezes its actually earned unlock")
	for attempt: int in range(6):
		if not await _open_cards():
			return false
		var slot: int = _find_card(func(action: Dictionary) -> bool: return BuildActions.specialization_candidate(action) == item)
		var world: Expedition = await _start(slot if slot >= 0 else _find_card(func(action: Dictionary) -> bool: return action.type == "supply"))
		if world == null:
			return false
		await _collect(world, 5)
		await _finish_outing(world)
		if slot >= 0:
			var build: Dictionary = app.camp_snapshot().journey.build
			var owned: bool = item in (build.powers.owned if special else build.owned)
			_check(owned, "actual search, bus and confirmation store the original signed reward")
			_write("reward.json", {"item":item, "returns":route, "owned":owned})
			return owned
	_check(false, "an ordinary signed gear action offered the earned reward")
	return false


func _radio_before() -> void:
	var radio: String = SpecialPowers.RADIO
	if not await _recover_specialty("support", radio, true) or not _edit({"kind":"power_equip", "member_id":0, "value":radio}):
		return
	var world: Expedition = await _ordinary_supply()
	if world == null:
		return
	_check(SpecialPowers.equipped_at(world.powers, 0) == radio, "the signed deployment equips the radio in its special slot")
	var first: FieldActor = world.search_member(1)
	var second: FieldActor = world.search_member(2)
	_check(first != null and second != null, "two living members deploy for the selection comparison")
	if first == null or second == null:
		return
	# Withhold both actors only for the no-target probe. No proposal is published.
	first.hide()
	second.hide()
	_check(not world.request_power(0) and world.basic_support.ready(radio)
		and "次数保留" in world._notice_text, "no eligible target gives feedback and preserves the charge")
	first.show()
	second.show()
	var lower: float = floorf(minf(second.health - 28.0, first.health / first.max_health * second.max_health - 20.0))
	_check(lower > 0.0 and second.take_damage(second.health - lower), "directed wound makes member 2 the lowest living fraction")
	var before: float = second.health
	world._update_ui()
	await _tap(world.power_panel.activation_button)
	var accepted: Array = world.basic_support.snapshot().accepted
	_check(accepted.size() == 1 and not world.basic_support.ready(radio), "radio confirmation consumes the one charge")
	if accepted.size() != 1:
		return
	var event: Dictionary = accepted[0]
	_check(event.kind == radio and event.facts.member_id == second.member_id and event.facts.amount == 24.0
		and second.health == before + 24.0 and not world.request_power(0), "original health proof targets member 2 and restores 24 HP once")
	await _suspend(world, "effect-checkpoint.json", {"event":event, "member_id":second.member_id,
		"health":second.health, "action":world.supply.generated.id, "scope":"DIRECTED_WOUND"})


func _reload_prepare() -> void:
	var saved: Dictionary = app.progress_session.inspect()
	var owned: Array = saved.get("camp", {}).get("journey", {}).get("build", {}).get("owned", [])
	if saved.get("state") == "CAMP" and BuildItems.GUIDED_MAG in owned:
		if not await _continue_trip():
			return
	elif not await _recover_specialty("firepower", BuildItems.GUIDED_MAG, false):
		return
	if CampFacilities.selected(app.camp_snapshot()) != CampFacilities.WORKSHOP and not _build(CampFacilities.WORKSHOP):
		return
	for attempt: int in range(6):
		if not await _open_cards():
			return
		var card: int = _find_card(func(action: Dictionary) -> bool: return not WorkshopSiteV1.site_id(action).is_empty())
		var world: Expedition = await _start(card if card >= 0 else _find_card(func(action: Dictionary) -> bool: return action.type == "supply"))
		if world == null:
			return
		if card >= 0:
			await _search(world, world._toolbox_site())
		await _food(world, 4)
		await _finish_outing(world)
		if WorkshopV1.tools(app.camp_snapshot()) > 0:
			break
	var camp: Dictionary = app.camp_snapshot()
	var item: Dictionary = WeaponInventory.for_member(camp, 1)
	var ready: bool = item.get("weapon_id") == "carbine" and WorkshopV1.tools(camp) > 0
	_check(ready, "normal workshop has an earned tool and the original carbine")
	if not ready:
		return
	if not _edit({"kind":WorkshopV1.QUICK, "member_id":0, "value":item.instance_id}):
		return
	_write("prepared.json", {"camp":RecordEncoding.fingerprint(app.camp_snapshot()), "weapon":item.instance_id, "returns":route})


func _reload_before(specialty: bool) -> void:
	var prepared: Dictionary = _read("reload-prepare/prepared.json")
	_check(RecordEncoding.fingerprint(app.camp_snapshot()) == prepared.camp,
		"same camp, gun, holder and modification underlie both arms")
	if specialty and not _edit({"kind":"build_slot", "member_id":1, "value":BuildItems.GUIDED_MAG}):
		return
	var world: Expedition = await _ordinary_supply()
	if world == null:
		return
	var actor: FieldActor = world.search_member(1)
	var gun: WeaponMagazine = actor.magazine
	_check(gun.instance_id == prepared.weapon and gun.modification == WorkshopV1.QUICK,
		"actual departure uses the same original modified weapon")
	_measure_initial(world, actor)
	await _drive(world, func() -> bool: return gun.reloading)
	_check(gun.reloading and shot_count == gun.capacity(), "actual attacks empty the complete carbine magazine")
	if not gun.reloading:
		return
	var start: float = world.elapsed
	var facts: Dictionary = {"weapon":gun.instance_id, "action":world.supply.generated.id, "seconds":gun.seconds(),
		"capacity":gun.capacity(), "attack":actor.weapon_definition.shot_interval(actor.trait_shot_factor),
		"move":actor.effective_speed(), "start":start}
	if not specialty:
		await _measure_reload_effect(world, actor, facts)
		return
	await _drive(world, func() -> bool: return gun.remaining < gun.seconds() - 0.2)
	_check(gun.reloading and gun.remaining > 0.0, "actual guided reload is in progress before suspend")
	await _suspend(world, "effect-checkpoint.json", facts.merged({"magazine":RecordEncoding.fingerprint(gun.snapshot())}))


func _effects_after(radio: bool) -> void:
	var world: Expedition = app.expedition
	var prior: Dictionary = _checkpoint(world, ("radio-before" if radio else "reload-before") + "/effect-checkpoint.json")
	if prior.is_empty():
		return
	var actor: FieldActor = world.search_member(int(prior.member_id) if radio else 1)
	await _unpause(world)
	if radio:
		var used: Array = world.basic_support.snapshot().accepted
		_check(used.size() == 1 and TransactionReceipt.same(used[0], prior.event) and actor.health == prior.health
			and not world.request_power(0), "fresh process preserves radio target, HP and exhausted use")
		_write("restored-effect.json", {"event":used[0], "health":actor.health, "source_pid":prior.pid, "pid":OS.get_process_id()})
	else:
		_check(RecordEncoding.fingerprint(actor.magazine.snapshot()) == prior.magazine,
			"fresh process preserves the exact partial guided reload")
		await _measure_reload_effect(world, actor, prior)


func _measure_reload_effect(world: Expedition, actor: FieldActor, facts: Dictionary) -> void:
	await _drive(world, func() -> bool: return not actor.magazine.reloading)
	var actual: float = world.elapsed - float(facts.start)
	_check(not actor.magazine.reloading and absf(actual - float(facts.seconds)) <= STEP + 0.0001,
		"the actual simulation clock completes the reload at the frozen effective duration")
	if output.get_file() == "reload-after":
		var baseline: Dictionary = _read("reload-baseline/reload.json")
		_check(baseline.weapon == facts.weapon and baseline.capacity == facts.capacity and baseline.action == facts.action
			and baseline.attack == facts.attack and baseline.move == facts.move
			and is_equal_approx(float(facts.seconds), float(baseline.seconds) * 0.90),
			"guided mag is exactly 0.90× the same gun, holder and workshop mod without changing other readouts")
	_write("reload.json", facts.merged({"elapsed":actual, "remaining":actor.magazine.remaining, "pid":OS.get_process_id()}, true))
