extends SceneTree
## Synthetic unit fixtures only. These do not represent a completed player route.

var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _run() -> void:
	var profile: String = "0123456789abcdef0123456789abcdef"
	var edit_id: String = profile + ":edit:abcdef0123456789abcdef0123456789"
	var legacy: Dictionary = {"profile_id":profile,"cash":20,"day":2}
	var legacy_request: Dictionary = EconomyBuildV1.request(legacy,"build","workshop","",edit_id)
	_check(EconomyBuildV1.propose(legacy,legacy_request).is_empty(),"legacy camp refuses an economy request without accessing absent ledger fields")
	_check(EconomyBuildV1.propose({},legacy_request).is_empty(),"empty context refuses an economy request")
	for gun: String in EconomyBuildV1.GUNS:
		var item: Dictionary = EconomyBuildV1.craft_instance(edit_id, gun)
		_check(WeaponModifiers.problem(item).is_empty(), "crafted " + gun)
		var damage: float = WeaponInventory.definition(gun).damage
		for tier: int in range(1, 6):
			item.weapon_level = tier
			_check(is_equal_approx(WeaponModifiers.effective(item).damage, damage * (1.0 + 0.1 * (tier - 1))), "damage " + gun + str(tier))
		item.weapon_level = 6
		_check(not WeaponModifiers.problem(item).is_empty(), "reject level6 " + gun)
		item.weapon_level = 1
		item.economy.basic = "quick_v1"
		item.economy.combat = WeaponModifiers.PIERCE
		item.affixes = EconomyBuildV1.components(item.economy)
		_check(WeaponModifiers.problem(item).is_empty(), "two components " + gun)
		_check(WeaponModifiers.combat_affix(item) == WeaponModifiers.PIERCE, "pierce " + gun)
		_check(is_equal_approx(WeaponModifiers.effective(item).interval, WeaponInventory.definition(gun).interval * 0.9), "quick " + gun)
		item.economy.basic = WeaponModifiers.PIERCE
		_check(not WeaponModifiers.problem(item).is_empty(), "reject combat in basic " + gun)
	for gun: String in ["carbine", "long_rifle", "shotgun_v1", "fire_axe_v1", CombatEquipment.HAMMER_ID]:
		for tier: int in range(1, 6):
			for quality: String in ["common", "enhanced", "rare", "crafted"]:
				var item: Dictionary = {"weapon_id":gun, "weapon_level":tier, "quality":quality, "condition":"ready"}
				var expected: int = (3 if gun in ["carbine", "fire_axe_v1"] else 4) + 2 * (tier - 1) + int({"enhanced":2, "rare":4}.get(quality, 0))
				_check(EconomyBuildV1.sale_price(item) == expected, "sale ready " + gun + quality + str(tier))
				item.condition = "damaged"
				_check(EconomyBuildV1.sale_price(item) == maxi(1, expected / 2), "sale damaged " + gun + quality + str(tier))
	var expected_magazines: Dictionary = {"carbine":{"extended_mag":[16, 2.20], "quick_mag":[9, 1.05]}, "long_rifle":{"extended_mag":[7, 2.55], "quick_mag":[3, 1.85]}, "shotgun_v1":{"extended_mag":[6, 3.00], "quick_mag":[3, 1.80]}}
	for gun: String in expected_magazines:
		for mod: String in expected_magazines[gun]:
			var expected: Array = expected_magazines[gun][mod]
			var parameters: Dictionary = WeaponMagazine.parameters(gun, mod)
			_check(parameters.capacity == expected[0] and is_equal_approx(parameters.seconds, expected[1]), "magazine " + gun + mod)
	var magazine: WeaponMagazine = WeaponMagazine.new("synthetic", "shotgun_v1", "extended_mag")
	_check(magazine.commit_shot(true) == 1 and magazine.rounds == 6, "one refund capacity ceiling")
	_check(magazine.commit_shot(false) == 0 and magazine.rounds == 5, "one trigger one round")
	var planning_fixture: Dictionary = {"profile_id":profile, "crew":[{"id":1}, {"id":2}, {"id":3}], "recruits":[{"member_id":3, "field_status":"RETURNED", "settlement_id":profile + ":2"}], "journey":{"deaths":[{"member_id":2, "transaction_id":profile + ":3"}]}}
	var parsed_fixture: Dictionary = JSON.parse_string(JSON.stringify(planning_fixture))
	_check(EconomyBuildV1.planning_eligible(parsed_fixture, 1, 1), "JSON numeric starter is eligible")
	_check(not EconomyBuildV1.planning_eligible(parsed_fixture, 5, 2), "unknown planning target rejected")
	_check(not EconomyBuildV1.planning_eligible(parsed_fixture, 3, 1), "planning cannot precede recruit registration")
	_check(EconomyBuildV1.planning_eligible(parsed_fixture, 3, 2), "returned recruit can receive planning on that return")
	_check(EconomyBuildV1.planning_eligible(parsed_fixture, 2, 2), "later death preserves earlier planning eligibility")
	_check(not EconomyBuildV1.planning_eligible(parsed_fixture, 2, 3), "planning after actual death rejected")
	parsed_fixture.recruits[0].field_status = "LOST"
	_check(not EconomyBuildV1.planning_eligible(parsed_fixture, 3, 2), "lost recruit cannot receive planning")
	var ownership_fixture: Dictionary = {"profile_id":profile, "crew":[{"id":1, "health":100.0}, {"id":2, "health":100.0}], "journey":{"campaign":{"economy":EconomyBuildV1.initial()}}}
	WeaponInventory.initialize(ownership_fixture, "initial")
	for index: int in range(ownership_fixture.weapons.size()): ownership_fixture.weapons[index] = WeaponModifiers.baseline(ownership_fixture.weapons[index])
	ownership_fixture.loadout[1].member_id = 1
	var parsed_ownership: Dictionary = JSON.parse_string(JSON.stringify(ownership_fixture))
	_check(EconomyBuildV1.weapon_problem(parsed_ownership) == "ECONOMY_LOADOUT", "JSON float duplicate owner rejected before projection")
	_projection_multi_source(profile)
	print("M48_ECONOMY_UNIT " + JSON.stringify({"checks":checks, "failures":failures, "synthetic":true}))
	quit(0 if failures.is_empty() else 1)


func _projection_multi_source(profile: String) -> void:
	# Minimal synthetic metadata exercises the already-authenticated projection helper.
	# Full action/source authentication remains covered by normal source/campaign flows.
	var site: Dictionary = {"id":"cash", "weapon":true, "drop":{"version":2, "weapon_id":"carbine"}}
	var action: Dictionary = {"version":9, "id":"first-source", "seed":"synthetic-source", "day":3, "slot":2, "type":"airdrop", "campaign":{"run_id":profile, "is_finale":false}, "sites":[site], "economy_source":{"version":1, "loot_grade":2, "tools":[], "hardware":false, "source_fields":{}}}
	var second: Dictionary = action.duplicate(true)
	second.id = "second-source"
	second.day = 4
	var newest: Dictionary = EconomyBuildV1.site_reward(profile + ":2", action, site)
	var old_action: Dictionary = EconomyActions.origin(second)
	var old_drop: Dictionary = WeaponInventory.site_reward(profile + ":3", old_action, site, true)
	var baseline: Dictionary = WeaponModifiers.baseline({"instance_id":profile + ":starter:1", "weapon_id":"carbine", "condition":"ready", "origin":"initial", "acquired_sortie":""})
	var camp: Dictionary = {"profile_id":profile, "day":5, "weapons":[baseline, newest, old_drop], "crew":[], "loadout":[], "training":[], "last_day":{}, "journey":{"campaign":{"economy":EconomyBuildV1.initial()}}}
	camp.journey.campaign.economy.sources = [{"transaction_id":profile + ":2", "action":action}, {"transaction_id":profile + ":3", "action":second}]
	var original_hash: String = RecordEncoding.fingerprint(camp)
	var projected: Dictionary = EconomyBuildV1.legacy_projection(camp)
	_check(not projected.is_empty(), "multiple sources project the matching new drop once")
	if projected.is_empty(): return
	var expected: Dictionary = WeaponInventory.site_reward(profile + ":2", EconomyActions.origin(action), site, true)
	_check(TransactionReceipt.same(WeaponInventory.find(projected, newest.instance_id), expected), "M48 drop uses its exact prior source shape")
	_check(TransactionReceipt.same(WeaponInventory.find(projected, old_drop.instance_id), old_drop), "old drop remains unchanged beside a new drop")
	_check(RecordEncoding.fingerprint(camp) == original_hash, "projection leaves the source camp unchanged")
	camp.journey.campaign.economy.sources.reverse()
	projected = EconomyBuildV1.legacy_projection(camp)
	_check(not projected.is_empty() and TransactionReceipt.same(WeaponInventory.find(projected, newest.instance_id), expected), "matching source may appear after an unrelated source")
