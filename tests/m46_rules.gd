extends SceneTree
## Directed policy and replay fixtures. These in-memory ledgers are not played returns.

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var isolated: String = ProjectSettings.globalize_path("res://.local/").replace("\\", "/")
	if not OS.get_user_data_dir().replace("\\", "/").begins_with(isolated):
		quit(2)
		return
	var app: Node = load("res://src/app/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app._new_game("scavenge", {"version": CatalogProgress.VERSION, "unlock": ""})
	var fresh: Dictionary = app.camp_snapshot()
	_check(CampFacilities.tier_two_enabled(fresh) and WorkshopV1.enabled(fresh), "fresh journey freezes V2 alongside M40 workshop")
	if CampFacilities.tier_two_enabled(fresh) and WorkshopV1.enabled(fresh):
		_facility_cases(fresh)
		_workshop_cases(fresh)
	_magazine_cases()
	app.audio.shutdown()
	app.queue_free()
	await process_frame
	print(JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures == 0 else 1)


func _facility_cases(fresh: Dictionary) -> void:
	var request: Dictionary = {"kind": "facility_upgrade", "value": CampFacilities.SUPPLY, "member_id": 0}
	_check(CampEdit.propose(fresh, request).is_empty(), "no upgrade before choosing a facility")
	var first: Dictionary = _returned(fresh, 4)
	var built: Dictionary = CampEdit.propose(first, {"kind": "facility", "value": CampFacilities.SUPPLY, "member_id": 0})
	_check(not built.is_empty() and CampEdit.propose(built, request).is_empty(), "construction debit does not count as another return")
	if built.is_empty():
		return
	var before: Dictionary = _returned(built, 1)
	var after: Dictionary = _edit_roundtrip(before, request)
	if after.is_empty():
		return
	_check(CampFacilities.upgraded(after) and after.cash == before.cash - 10 and after.camp_spending == before.camp_spending + 10
		and TransactionReceipt.same(after.last_day, before.last_day) and CampEdit.propose(after, request).is_empty(),
		"exact debit, previous ledger retained, and duplicate denied")
	_check(CampFacilities.offered_food(after, int(before.last_day.day), true) == 2
		and CampFacilities.offered_food(after, int(after.day), false) == 0, "upgrade only applies to future successful returns")
	var settled: Dictionary = _returned(after, 0)
	var result: Dictionary = {"food": CampEconomy.post_battle_food(int(after.day), after.crew, int(after.food), 0, 1, true, 3),
		"battle": {"food": 0, "evacuated": true}}
	_check(settled.last_day.facility_food == 3 and TransactionReceipt.camp_problem(settled).is_empty()
		and CampFacilities.result_problem(after, settled, result).is_empty(), "later ledger credits exactly three and validates from departure")
	var overflow: Dictionary = CampEconomy.post_battle_food(int(after.day), after.crew, CampRules.FOOD_LIMIT - 2, 1, 1, true, 3)
	_check(overflow.facility_stored == 1 and overflow.facility_food - overflow.facility_stored == 2
		and not SurvivalContracts.food_problem(overflow).is_empty(), "capacity tracks facility overflow and legacy validation rejects tier-two ledger")
	var old: Dictionary = before.duplicate(true)
	old.journey.campaign.midgame.version = CampFacilities.VERSION
	old.journey.campaign.midgame.erase("upgraded_day")
	_check(TransactionReceipt.camp_problem(old).is_empty() and CampEdit.propose(old, request).is_empty()
		and CampFacilities.offered_food(old, int(old.day), true) == 2, "legacy camp keeps the original ledger and cannot opt into tier two")


func _workshop_cases(fresh: Dictionary) -> void:
	var first: Dictionary = _returned(fresh, 4)
	var built: Dictionary = CampEdit.propose(first, {"kind": "facility", "value": CampFacilities.WORKSHOP, "member_id": 0})
	if built.is_empty():
		_check(false, "valid first return can build workshop")
		return
	var tooling: Dictionary = {}
	for action: Dictionary in DailyActions.offers(built):
		var site: String = WorkshopSiteV1.site_id(action)
		if not site.is_empty():
			tooling = WorkshopV1.settled(built, action, {"evacuated": true, "site_facts": {site: {"searched": true}}})
			break
	if tooling.is_empty():
		_check(false, "fixture requires --bh-rescue-seed=m38-wave-01 to reproduce the original day-three toolbox route")
		return
	var before: Dictionary = _returned(built, 2)
	before.journey.campaign.workshop = tooling
	var rifle: Dictionary = WeaponInventory.for_member(before, 2)
	var request: Dictionary = {"kind": "facility_upgrade", "value": CampFacilities.WORKSHOP, "member_id": 0}
	_check(WorkshopV1.tools(before) == 1 and not WorkshopV1.mod_problem(before, rifle.instance_id, WorkshopV1.EXTENDED).is_empty(),
		"real toolbox source alone does not unlock long rifle")
	var calibrated: Dictionary = _edit_roundtrip(before, request)
	if calibrated.is_empty():
		return
	for mod: String in [WorkshopV1.EXTENDED, WorkshopV1.QUICK]:
		var installed: Dictionary = _edit_roundtrip(calibrated, {"kind": mod, "value": rifle.instance_id, "member_id": 0})
		if installed.is_empty():
			continue
		_check(installed.cash == calibrated.cash - 8 and WorkshopV1.tools(installed) == 0
			and WorkshopV1.mod_for(installed, rifle.instance_id) == mod
			and installed.weapons == calibrated.weapons and installed.loadout == calibrated.loadout
			and not WorkshopV1.mod_problem(installed, rifle.instance_id, mod).is_empty(), "one toolbox and eight coins, exact instance provenance: " + mod)


func _edit_roundtrip(before: Dictionary, request: Dictionary) -> Dictionary:
	var identity: String = "%s:edit:%s" % [before.profile_id, "1".repeat(32)]
	var receipt: Dictionary = CampEdit.record(before, request, identity, {"root_id": before.journey.root_id, "revision": 3, "deaths": []})
	_check(not receipt.is_empty(), "valid frozen edit: " + request.kind)
	if receipt.is_empty():
		return {}
	var decoded: Dictionary = RecordEncoding.unpack(JSON.parse_string(RecordEncoding.stringify(receipt))).payload
	_check(TransactionReceipt.problem(decoded).is_empty(), "independent exact decoding and recomputation: " + request.kind)
	var forged: Dictionary = decoded.duplicate(true)
	forged.envelope.result.cash += 1
	forged.envelope.after_hash = SurvivalContracts.fingerprint(forged.envelope.result)
	_check(not TransactionReceipt.problem(forged).is_empty(), "rehashing a forged debit does not authorize it: " + request.kind)
	return decoded.envelope.result


func _returned(before: Dictionary, field_food: int) -> Dictionary:
	var after: Dictionary = before.duplicate(true)
	after.day = int(before.day) + 1
	after.settled_sorties = int(before.settled_sorties) + 1
	after.last_settlement_id = "%s:%d" % [before.profile_id, after.settled_sorties]
	var facility_food: int = CampFacilities.offered_food(before, int(before.day), true)
	after.last_day = CampEconomy.post_battle_food(int(before.day), before.crew, int(before.food), field_food, 1, true, facility_food)
	after.food = after.last_day.food_after
	after.camp_spending = 0
	after.last_day.merge({"day": before.day, "settlement_id": after.last_settlement_id, "evacuated": true,
		"cash_before": before.cash, "cash_after": after.cash, "cash_gained": 0})
	return after


func _magazine_cases() -> void:
	for mod: String in [WorkshopV1.EXTENDED, WorkshopV1.QUICK]:
		var magazine: WeaponMagazine = WeaponMagazine.new("rifle-fixture", "long_rifle", mod)
		magazine.reload_factor = 1.15
		var extended: bool = mod == WorkshopV1.EXTENDED
		_check(magazine.capacity() == (7 if extended else 3)
			and is_equal_approx(magazine.seconds(), (2.55 if extended else 1.85) * 1.15), "base and effective rifle parameters: " + mod)
		for shot: int in range(magazine.capacity()):
			magazine.commit_shot()
		var snapshot: Dictionary = magazine.snapshot()
		_check(WeaponMagazine.problem(snapshot, "rifle-fixture", "long_rifle", 1.15, mod).is_empty()
			and not WeaponMagazine.problem(snapshot, "rifle-fixture", "long_rifle", 1.0, mod).is_empty()
			and not WeaponMagazine.problem(snapshot, "rifle-fixture", "long_rifle", 1.15).is_empty(),
			"snapshot enforces frozen instance, installed scheme, and holder factor: " + mod)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("M46_RULES_FAIL " + message)
