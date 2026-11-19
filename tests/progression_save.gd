extends "res://tests/harbor_warehouse.gd"
## Directed searches/hits in real worlds, frozen settlement and isolated transaction I/O.
## This is a contract fixture, not evidence of an unassisted player campaign.

var _transaction: RunTransaction
var _path: String


func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(ProjectSettings.globalize_path("res://.local/")):
		quit(2)
		return
	var base: Dictionary = _harbor_camp()
	base.day = 2
	base.settled_sorties = 0
	var opening: Dictionary = OpeningBuild.source("scavenge", base.profile_id, base.journey.root_id, base.journey.seed, {"version":OpeningBuild.POLICY_VERSION, "eligible":[]})
	base.journey.build.opening = opening
	base.journey.build.owned.append(opening.item_id)
	base.journey.build.slots[0] = opening.item_id
	base.journey.build.catalog = {"version":CatalogProgress.VERSION, "unlock":""}
	expect(TransactionReceipt.camp_problem(base).is_empty(), "initial progression fixture authenticates: " + TransactionReceipt.camp_problem(base))
	_path = ProjectSettings.globalize_path("res://.local/progression-save-" + RunSave.new_profile_id() + "/run.enemy-v1.json")
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	var save: RunSave = RunSave.new(_path, false, false, false, false, false, false, false, false, false, false, true)
	var writer: ProgressWriter = ProgressWriter.new(_path)
	expect(writer.acquire() == OK, "test owns isolated save writer")
	expect(save.save(base, true, writer) == OK, "initial fixture writes only under local test directory: " + save.diagnostic)
	writer.release()
	_transaction = RunTransaction.new(_path + ".txn/journal", _path, base.profile_id, base.journey.root_id)
	if not _ok(_transaction.register(base), "register source camp"):
		_done()
		return
	base = _return_fixture(base, false, true)
	if base.is_empty():
		_done()
		return
	var first: Dictionary = SurvivorRoster.member(base.crew, 1)
	expect(first.growth.level >= 2 and first.growth.xp_total >= 30 and GrowthRules.maximum(first) >= 205.0, "real defeat ledger banks level and HP in frozen settlement")
	base = _return_fixture(base, true)
	if base.is_empty():
		_done()
		return
	base = _edit(base, "build", "workshop")
	if base.is_empty():
		_done()
		return
	base = _return_fixture(base, false)
	if base.is_empty():
		_done()
		return
	base = _edit(base, "upgrade_facility", "workshop")
	if base.is_empty():
		_done()
		return
	var weapon_id: String = WeaponInventory.for_member(base, 1).instance_id
	var prior: Dictionary = WeaponInventory.find(base, weapon_id).duplicate(true)
	var offers_hash: String = RecordEncoding.fingerprint({"offers":DailyActions.offers(base)})
	base = _edit(base, "upgrade_weapon", weapon_id)
	if base.is_empty():
		_done()
		return
	var upgraded: Dictionary = WeaponInventory.find(base, weapon_id)
	expect(upgraded.instance_id == prior.instance_id and upgraded.weapon_level == prior.weapon_level + 1 and upgraded.affixes == prior.affixes, "starter upgrades preserve identity and affixes")
	expect(WeaponModifiers.effective(upgraded).damage > WeaponModifiers.effective(prior).damage, "same starter gun improves next-sortie damage")
	var tampered: Dictionary = base.duplicate(true)
	WeaponInventory.find(tampered, weapon_id).weapon_level += 1
	expect(not TransactionReceipt.camp_problem(tampered).is_empty(), "unpaid weapon level fails provenance replay")
	var trait_before: int = int(SurvivorRoster.member(base.crew, 1).growth.trait.progress)
	var level_before: int = int(SurvivorRoster.member(base.crew, 1).growth.trait.level)
	for lesson: int in range(3):
		var quote: Dictionary = TrainingRules.preview(base, 1)
		if not quote.error.is_empty():
			expect(false, "training is available: " + quote.error)
			_done()
			return
		base = _persist_edit(base, quote.request, TrainingRules.intent_for(quote.request).edit_id)
		if base.is_empty():
			_done()
			return
	expect(SurvivorRoster.member(base.crew, 1).growth.trait.progress == trait_before + 3 and SurvivorRoster.member(base.crew, 1).growth.trait.level > level_before, "paid training crosses the next personal trait threshold")
	expect(RecordEncoding.fingerprint({"offers":DailyActions.offers(base)}) == offers_hash, "weapon and training edits leave today's offers fingerprints unchanged")
	var fresh: RunTransaction = RunTransaction.new(_path + ".txn/journal", _path, base.profile_id, base.journey.root_id)
	var loaded: Dictionary = fresh.recover()
	if _ok(loaded, "fresh transaction reader recovers confirmed upgrades"):
		var restored: Dictionary = TransactionReceipt.camp(loaded.receipt)
		expect(TransactionReceipt.same(base, restored), "levels traits facilities and weapon instances round-trip exactly")
		var world: Expedition = _new_field(restored, DailyActions.supply(DailyActions.offers(restored)[0]))
		var actor: FieldActor = world.search_member(1)
		var personal: Dictionary = SurvivorPersona.factors(PersonaState.recipe(world.supply.generated, 1, &"crew_1"))
		expect(actor.max_health == GrowthRules.maximum(SurvivorRoster.member(restored.crew, 1)), "next-sortie actor uses restored grown HP")
		expect(near(actor.magazine.reload_factor, personal.reload * BuildItems.camp_factors(restored).reload * 0.90), "next-sortie actor uses restored tier-two workshop")
		expect(actor.weapon_instance_id == weapon_id and actor.weapon_definition.damage > WeaponInventory.definition("carbine").damage, "next-sortie actor holds the strengthened original instance")
		world.bus_view.skip()
		world.toggle_pause()
		var rules: Dictionary = FrozenSettlement.pool_rules(restored, world.supply)
		var receipt: Dictionary = TransactionReceipt.initial(restored, world.sortie_id, rules, loaded.receipt)
		var snapshot: Dictionary = SortieSnapshot.capture(world)
		var snapshot_issue: String = SortieSnapshot.problem(snapshot, receipt)
		expect(snapshot_issue.is_empty(), "workshop reload survives strict snapshot validation: " + snapshot_issue)
		var rebuilt: Expedition = _new_field(restored, world.supply)
		var restore_issue: String = SortieSnapshot.apply(rebuilt, snapshot)
		expect(restore_issue.is_empty(), "workshop reload survives world reconstruction: " + restore_issue)
		rebuilt.get_viewport().free()
		world.get_viewport().free()
	_facility_returns(base)
	_done()


func _ok(result: Dictionary, label: String) -> bool:
	var accepted: bool = result.get("error") == OK
	expect(accepted, label + ": " + String(result.get("reason", "")))
	return accepted


func _edit(base: Dictionary, op: String, target: String) -> Dictionary:
	var identity: String = base.profile_id + ":edit:" + RunSave.new_profile_id()
	return _persist_edit(base, EconomyBuildV1.request(base, op, target, "", identity), identity)


func _persist_edit(base: Dictionary, request: Dictionary, identity: String) -> Dictionary:
	var head: Dictionary = _transaction.recover()
	if not _ok(head, "read edit head"):
		return {}
	if not _ok(_transaction.prepare_edit(head.hash, identity, request), "prepare " + request.kind):
		return {}
	var committed: Dictionary = _transaction.commit_edit(identity)
	if not _ok(committed, "commit " + request.kind):
		return {}
	var result: Dictionary = TransactionReceipt.camp(committed.receipt)
	expect(not TransactionReceipt.same(base, result), "edit has a concrete saved effect")
	return result


func _return_fixture(base: Dictionary, hardware: bool, defeats: bool = false) -> Dictionary:
	var offers: Array[Dictionary] = DailyActions.offers(base)
	var action: Dictionary = offers[0]
	if hardware:
		for candidate: Dictionary in offers:
			if EconomyActions.hardware(candidate):
				action = candidate
		expect(EconomyActions.hardware(action), "scheduled hardware source funds construction without injected tools")
	var supply: MissionSupply = DailyActions.supply(action)
	var rules: Dictionary = FrozenSettlement.pool_rules(base, supply)
	var begun: Dictionary = _transaction.begin(base, "%s:%d" % [base.profile_id, int(base.settled_sorties) + 1], rules)
	if not _ok(begun, "begin directed sortie"):
		return {}
	var world: Expedition = _new_field(base, supply)
	world.bus_view.skip()
	if defeats:
		for index: int in range(3):
			world._spawn_enemy()
			var enemy: FieldActor = world.enemies.back()
			var recorded: Array[Dictionary] = []
			world.elapsed += 1.0
			# Directed hit input enters the real damage and defeat-ledger owner.
			world._combat._commit_ranged_hit(world.survivors[0], enemy, enemy.health, recorded)
	for site: Expedition.SearchSite in world.sites:
		if site.searched or site == world.recon_site or site == world.billboard_site:
			continue
		var actor: FieldActor = world.survivors[1]
		actor.position = site.door
		world._assign_search(site, actor, PackedVector2Array([site.door]))
		for tick: int in range(6000):
			world.elapsed += 0.05
			world._update_search(0.05)
			if site.searched or world.is_paused:
				break
		expect(site.searched, "real search integrator completes " + String(site.id))
	var reports: Array[Dictionary] = []
	world.finished.connect(func(report: Dictionary) -> void: reports.append(report))
	world._finish(true)
	var input: Dictionary = {"before":base, "token":begun.token, "participants":SurvivalContracts.participants(base.crew, WeaponInventory.snapshot(base), true, true),
		"rules":rules, "report":reports[0], "carried":{"loot":world.loot, "food":world.food_loot, "weapons":world.weapon_loot.duplicate(true)},
		"prior_deaths":base.journey.deaths, "completion":"COMPLETED", "searching_member_ids":[]}
	var computed: Dictionary = FrozenSettlement.compute(input)
	world.get_viewport().free()
	if not computed.error.is_empty():
		expect(false, "frozen settlement accepts directed report: " + String(computed.get("reason", computed.error)))
		return {}
	if not _ok(FrozenSettlement.prepare_pool(_transaction, computed.packet), "prepare frozen return"):
		return {}
	var committed: Dictionary = _transaction.commit(begun.token)
	return TransactionReceipt.camp(committed.receipt) if _ok(committed, "commit frozen return") else {}


func _new_field(base: Dictionary, supply: MissionSupply) -> Expedition:
	var world: Expedition = Expedition.new()
	world.supply = supply
	world.battle_survival = true
	world.sortie_id = "%s:%d" % [base.profile_id, int(base.settled_sorties) + 1]
	world.day = int(base.day)
	world.crew_snapshot.assign(base.crew)
	world.loadout_snapshot = WeaponInventory.snapshot(base)
	world.field_departure = base
	world.growth_binding = {"run_id":base.profile_id, "root_id":base.journey.root_id, "transaction_id":world.sortie_id,
		"base_hash":SurvivalContracts.fingerprint(base), "rules_hash":SurvivalContracts.fingerprint(FrozenSettlement.pool_rules(base, supply))}
	world.ui_theme = preload("res://assets/ui/c1/hud_theme.tres")
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.world_2d = World2D.new()
	viewport.gui_embed_subwindows = true
	root.add_child(viewport)
	viewport.add_child(world)
	for actor: FieldActor in world.survivors:
		actor.permanent_death_enabled = true
	world.set_process(false)
	world.set_physics_process(false)
	return world


func _facility_returns(base: Dictionary) -> void:
	for tier: int in range(3):
		# Pure directed boundary fixture: these copies never claim earned construction.
		var source: Dictionary = base.duplicate(true)
		var ledger: Dictionary = EconomyBuildV1.state(source)
		ledger.edits = []
		for id: String in EconomyBuildV1.FACILITIES:
			ledger.facilities[id].level = tier
			for step: int in range(tier):
				ledger.edits.append({"sortie":0, "target":id, "op":"build" if step == 0 else "upgrade_facility"})
		var after: Dictionary = source.duplicate(true)
		for member: Dictionary in after.crew:
			member.growth.trait = {"id":TraitRules.IDS[TraitRules.role(member) - 1], "level":1, "progress":0}
		var report: Dictionary = {"sortie_id":"directed-return", "evacuated":true, "food":4, "site_facts":{}}
		EconomyBuildV1.settled(source, after, report, {})
		var returned: Dictionary = EconomyBuildV1.state(after).returns.back()
		expect(returned.field_food == 4 and returned.food == tier, "supply tier caps the processed rations from this harvest")
		expect(returned.planning.is_empty() if tier == 0 else returned.planning.points == tier, "planning tier controls next-return trait award")
		var failed: Dictionary = source.duplicate(true)
		report.evacuated = false
		EconomyBuildV1.settled(source, failed, report, {})
		expect(TransactionReceipt.same(source, failed), "failed extraction grants no facility return benefit")


func _done() -> void:
	print("BH_PROGRESSION_SAVE " + JSON.stringify({"checks":checks, "failures":failures, "profile":_path}))
	quit(0 if failures == 0 else 1)
